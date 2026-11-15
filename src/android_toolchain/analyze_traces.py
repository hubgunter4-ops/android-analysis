#!/usr/bin/env python3
"""Analiza y clasifica trazas ADB capturadas (y bugreports).

Entrada: una carpeta de captura (`~/security-tools/traces/<fecha>_<serial>/`),
uno o varios archivos sueltos (.txt o .zip de bugreport), o un bugreport.zip.

Clasificación por archivo (fuente) y por línea:
  - clase: reinicio-energia, crash, anr, memoria, permisos, red,
    almacenamiento, kernel, proceso, otros (en ese orden de prioridad).
  - severidad: del nivel logcat (E/F alta, W media, resto baja) cuando la
    línea trae formato logcat; si no, de la clase (reinicio/crash/anr/
    kernel alta; memoria/permisos/red/almacenamiento media; proceso baja).

El análisis es de solo lectura sobre la entrada. La salida es un reporte
ANALISIS.txt + resumen.json + MANIFIESTO.txt (SHA-256 de entradas y
salidas) en ~/security-tools/analyses/ANALISIS-<fecha>_<etiqueta>/.

Un bugreport.zip se extrae a un temporal (0700), se escanea el .txt
principal y se borra al terminar; el crudo nunca se copia al reporte,
solo conteos y muestras redactadas de una línea.

Uso:
  analyze_traces.py --dir DIR | --file ARCHIVO [--file ...]
                    [--out-dir PATH] [--max-muestras N]
                    [--dry-run | --plan-json]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import zipfile
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

VERSION = "2.1.0"
DEFAULT_OUT_DIR = Path.home() / "security-tools" / "analyses"
MAX_LINEAS_POR_ARCHIVO = 500_000

# (clase, etiqueta, severidad por defecto, patrones en orden de prioridad)
REGLAS: list[tuple[str, str, str, list[str]]] = [
    ("reinicio-energia", "Reinicio / energía", "alta", [
        r"2sec_reboot", r"power status Exception", r"reboot reason",
        r"RESET_REASON", r"boot reason", r"kernel panic",
        r"watchdog bark", r"thermal shutdown", r"power reset",
        r"\breboot\b", r"\bshutdown\b", r"last_kmsg",
    ]),
    ("crash", "Crash de app o proceso", "alta", [
        r"FATAL EXCEPTION", r"tombstone", r"Force finishing activity",
        r"has died", r"\bSIGSEGV\b", r"signal 11", r"signal 6",
        r"\babort\b", r"Application .* has stopped",
    ]),
    ("anr", "ANR (app sin responder)", "alta", [
        r"\bANR\b", r"Application Not Responding", r"ANR in ",
        r"Input dispatching timed out",
    ]),
    ("memoria", "Memoria", "media", [
        r"OutOfMemory", r"lowmemorykiller", r"onTrimMemory",
        r"\boom\b", r"low memory", r"Out of memory",
    ]),
    ("permisos", "Permisos / seguridad", "media", [
        r"SecurityException", r"permission denied", r"avc:  denied",
        r"\bSELinux\b", r"Not allowed to",
    ]),
    ("red", "Red", "media", [
        r"NetworkCallback", r"connect timed out", r"SocketTimeout",
        r"UnknownHost", r"Network unreachable", r"ECONNREFUSED",
        r"SSLHandshakeException",
    ]),
    ("almacenamiento", "Almacenamiento", "media", [
        r"No space left", r"I/O error", r"fsync failed", r"disk full",
    ]),
    ("kernel", "Kernel", "alta", [
        r"\bpanic\b", r"\boops\b", r"hung task", r"blocked for more than",
        r"\bBUG:", r"Call Trace", r"\bmmc\b.*error",
    ]),
    ("proceso", "Proceso", "baja", [
        r"Force stopping", r"\bKilling\b", r"Scheduling restart",
        r"start proc", r"\bzygote\b", r"app died",
    ]),
]
CLASES = [c for c, _, _, _ in REGLAS] + ["otros"]
PATRONES = [(c, s, re.compile(p, re.IGNORECASE))
            for c, _, s, ps in REGLAS for p in ps]
LOGCAT_NIVEL = re.compile(
    r"^\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\s+\d+\s+\d+\s+([EFWDVI])\s")
# Archivos de captura conocidos (01-08) y su descripción.
FUENTES_CONOCIDAS = {
    "01-procesos-ps-A.txt": "Procesos (ps -A)",
    "02-procesos-top.txt": "Procesos (top)",
    "03-logcat-errores.txt": "Logcat de errores",
    "04-logcat-crash.txt": "Logcat de crashes",
    "05-logcat-sistema.txt": "Logcat del sistema",
    "06-kernel-dmesg.txt": "Kernel (dmesg)",
    "07-kernel-anterior-pstore.txt": "Kernel anterior (pstore)",
    "08-fallos-dropbox.txt": "Fallos (dropbox)",
}


def sha256_de(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for bloque in iter(lambda: f.read(1 << 20), b""):
            h.update(bloque)
    return h.hexdigest()


def clasificar_linea(linea: str) -> tuple[str, str]:
    """Devuelve (clase, severidad) de una línea; 'otros' si no casa."""
    m = LOGCAT_NIVEL.match(linea)
    nivel = m.group(1) if m else None
    for clase, severidad, patron in PATRONES:
        if patron.search(linea):
            if nivel in ("E", "F"):
                severidad = "alta"
            elif nivel == "W" and severidad == "baja":
                severidad = "media"
            return clase, severidad
    if nivel in ("E", "F"):
        return "otros", "alta"
    if nivel == "W":
        return "otros", "media"
    return "otros", "baja"


@dataclass
class ResultadoArchivo:
    nombre: str
    descripcion: str
    lineas: int = 0
    por_clase: dict[str, int] = field(default_factory=lambda: {c: 0 for c in CLASES})
    por_severidad: dict[str, int] = field(
        default_factory=lambda: {"alta": 0, "media": 0, "baja": 0})
    muestras: dict[str, list[str]] = field(default_factory=dict)
    truncado: bool = False

    def agregar(self, linea: str, numero: int, max_muestras: int) -> None:
        clase, severidad = clasificar_linea(linea)
        self.lineas += 1
        self.por_clase[clase] += 1
        self.por_severidad[severidad] += 1
        if clase != "otros" and len(self.muestras.get(clase, [])) < max_muestras:
            muestra = linea.rstrip("\n")
            if len(muestra) > 300:
                muestra = muestra[:297] + "..."
            self.muestras.setdefault(clase, []).append(f"L{numero}: {muestra}")


def analizar_texto(path: Path, descripcion: str, max_muestras: int) -> ResultadoArchivo:
    r = ResultadoArchivo(nombre=path.name, descripcion=descripcion)
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for i, linea in enumerate(f, 1):
            if i > MAX_LINEAS_POR_ARCHIVO:
                r.truncado = True
                break
            r.agregar(linea, i, max_muestras)
    return r


def analizar_bugreport_zip(path: Path, max_muestras: int) -> ResultadoArchivo:
    """Extrae el .txt principal de un bugreport.zip y lo clasifica."""
    tmp = Path(tempfile.mkdtemp(prefix="analisis-bugreport-"))
    os.chmod(tmp, 0o700)
    try:
        with zipfile.ZipFile(path) as z:
            candidatos = [n for n in z.namelist()
                          if n.lower().endswith(".txt") and not n.endswith("/")]
            if not candidatos:
                raise ValueError("el zip no contiene ningún .txt")
            principal = max(candidatos, key=lambda n: z.getinfo(n).file_size)
            z.extract(principal, tmp)
        extraido = tmp / principal
        r = analizar_texto(extraido, f"Bugreport ({principal})", max_muestras)
        r.nombre = path.name
        return r
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def describir(path: Path) -> str:
    if path.name in FUENTES_CONOCIDAS:
        return FUENTES_CONOCIDAS[path.name]
    if path.suffix == ".zip":
        return "Bugreport (zip)"
    return "Archivo de registro"


def recolectar_entradas(directorio: Path | None,
                        archivos: list[Path]) -> list[Path]:
    entradas: list[Path] = []
    if directorio is not None:
        if not directorio.is_dir():
            raise ValueError(f"carpeta no encontrada: {directorio}")
        for p in sorted(directorio.iterdir()):
            if p.is_file() and (p.suffix in (".txt", ".zip")):
                entradas.append(p)
        if not entradas:
            raise ValueError(f"sin archivos .txt ni .zip en {directorio}")
    for p in archivos:
        if not p.is_file():
            raise ValueError(f"archivo no encontrado: {p}")
        if p.suffix not in (".txt", ".zip"):
            raise ValueError(f"solo se aceptan .txt o .zip: {p}")
        entradas.append(p)
    if not entradas:
        raise ValueError("indica --dir o --file")
    return entradas


def etiqueta_de(entradas: list[Path], directorio: Path | None) -> str:
    if directorio is not None and "_" in directorio.name:
        return directorio.name.split("_", 1)[1]
    if len(entradas) == 1 and entradas[0].suffix == ".zip":
        return "bugreport"
    return "archivo" if len(entradas) == 1 else "varios"


def plan(entradas: list[Path], out_dir: Path) -> dict:
    return {
        "version": VERSION,
        "entradas": [str(p) for p in entradas],
        "archivos": [p.name for p in entradas],
        "clases": CLASES,
        "salida": str(out_dir),
    }


def escribir_reporte(resultados: list[ResultadoArchivo], entradas: list[Path],
                     run_dir: Path, fecha: str) -> tuple[Path, Path, Path]:
    total_lineas = sum(r.lineas for r in resultados)
    por_clase = {c: sum(r.por_clase[c] for r in resultados) for c in CLASES}
    por_sev = {s: sum(r.por_severidad[s] for r in resultados)
               for s in ("alta", "media", "baja")}
    top = sorted(((c, n) for c, n in por_clase.items() if c != "otros" and n),
                 key=lambda x: -x[1])

    lineas = []
    lineas.append("ANÁLISIS DE TRAZAS ADB")
    lineas.append(f"Fecha: {fecha}")
    lineas.append(f"Archivos analizados: {len(resultados)}")
    lineas.append(f"Líneas totales: {total_lineas}")
    lineas.append("")
    lineas.append("RESUMEN POR CLASE")
    for clase, n in sorted(por_clase.items(), key=lambda x: -x[1]):
        if n:
            lineas.append(f"  {clase}: {n}")
    lineas.append("")
    lineas.append("RESUMEN POR SEVERIDAD")
    for sev in ("alta", "media", "baja"):
        lineas.append(f"  {sev}: {por_sev[sev]}")
    lineas.append("")
    lineas.append("HALLAZGOS PRINCIPALES")
    if not top:
        lineas.append("  Sin líneas clasificadas fuera de 'otros'.")
    for clase, n in top:
        lineas.append(f"  {clase}: {n} líneas")
    lineas.append("")
    for r in resultados:
        lineas.append(f"== {r.nombre} — {r.descripcion} "
                      f"({r.lineas} líneas"
                      f"{', truncado a 500000' if r.truncado else ''}) ==")
        for clase, n in sorted(r.por_clase.items(), key=lambda x: -x[1]):
            if n:
                lineas.append(f"  {clase}: {n}")
        for clase, muestras in r.muestras.items():
            lineas.append(f"  Muestras de {clase}:")
            for m in muestras:
                lineas.append(f"    {m}")
        lineas.append("")
    lineas.append("Nota: el reporte muestra conteos y muestras de una línea; "
                 "el crudo nunca se copia aquí. Revisa las muestras antes "
                 "de concluir una causa.")

    analisis = run_dir / "ANALISIS.txt"
    analisis.write_text("\n".join(lineas), encoding="utf-8")

    resumen = {
        "version": VERSION,
        "fecha": fecha,
        "entradas": [str(p) for p in entradas],
        "total_lineas": total_lineas,
        "por_clase": por_clase,
        "por_severidad": por_sev,
        "por_archivo": [{
            "archivo": r.nombre,
            "descripcion": r.descripcion,
            "lineas": r.lineas,
            "truncado": r.truncado,
            "por_clase": {c: n for c, n in r.por_clase.items() if n},
            "por_severidad": r.por_severidad,
            "muestras": r.muestras,
        } for r in resultados],
    }
    resumen_path = run_dir / "resumen.json"
    resumen_path.write_text(json.dumps(resumen, indent=2, ensure_ascii=False),
                            encoding="utf-8")

    manifiesto = run_dir / "MANIFIESTO.txt"
    m = ["MANIFIESTO DE ANÁLISIS DE TRAZAS ADB", f"Fecha: {fecha}", "",
         "ENTRADAS"]
    for p in entradas:
        m.append(f"  {p.name}  {p.stat().st_size} B  {sha256_de(p)}")
    m += ["", "SALIDAS"]
    for p in (analisis, resumen_path):
        m.append(f"  {p.name}  {p.stat().st_size} B  {sha256_de(p)}")
    manifiesto.write_text("\n".join(m) + "\n", encoding="utf-8")
    return analisis, resumen_path, manifiesto


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Analiza y clasifica trazas ADB capturadas.")
    ap.add_argument("--dir", dest="dir", type=Path,
                    help="carpeta de captura con .txt y/o .zip")
    ap.add_argument("--file", dest="files", action="append", type=Path,
                    default=[], help="archivo .txt o .zip (repetible)")
    ap.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR,
                    help="directorio base de evidencia")
    ap.add_argument("--max-muestras", type=int, default=5,
                    help="muestras por clase y archivo (default: 5)")
    ap.add_argument("--dry-run", action="store_true",
                    help="solo muestra el plan, sin analizar ni escribir")
    ap.add_argument("--plan-json", action="store_true",
                    help="muestra el plan en JSON y sale")
    ap.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    args = ap.parse_args(argv)

    if args.max_muestras < 0 or args.max_muestras > 50:
        print("error: --max-muestras entre 0 y 50", file=sys.stderr)
        return 2
    try:
        entradas = recolectar_entradas(args.dir, args.files)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    fecha = datetime.now().strftime("%Y%m%d-%H%M%S")
    etiqueta = etiqueta_de(entradas, args.dir)
    run_dir = args.out_dir / f"ANALISIS-{fecha}_{etiqueta}"

    if args.plan_json:
        print(json.dumps(plan(entradas, run_dir), indent=2, ensure_ascii=False))
        return 0
    print("PLAN DE ANÁLISIS DE TRAZAS (dry-run, sin cambios)"
          if args.dry_run else "ANÁLISIS DE TRAZAS ADB")
    print(f"Versión: {VERSION} | archivos: {len(entradas)} | "
          f"salida: {run_dir}")
    for p in entradas:
        print(f"  + {p.name} — {describir(p)}")
    if args.dry_run:
        return 0

    resultados: list[ResultadoArchivo] = []
    for p in entradas:
        try:
            if p.suffix == ".zip":
                resultados.append(analizar_bugreport_zip(p, args.max_muestras))
            else:
                resultados.append(
                    analizar_texto(p, describir(p), args.max_muestras))
        except (OSError, ValueError, zipfile.BadZipFile) as exc:
            print(f"aviso: no se pudo analizar {p.name}: {exc}", file=sys.stderr)
    if not resultados:
        print("error: ningún archivo pudo analizarse", file=sys.stderr)
        return 3

    run_dir.mkdir(parents=True, mode=0o700, exist_ok=True)
    analisis, resumen_path, manifiesto = escribir_reporte(
        resultados, entradas, run_dir, fecha)
    os.chmod(analisis, 0o600)
    os.chmod(resumen_path, 0o600)
    os.chmod(manifiesto, 0o600)

    total = sum(r.lineas for r in resultados)
    top = sorted(((c, sum(r.por_clase[c] for r in resultados))
                  for c in CLASES if c != "otros"),
                 key=lambda x: -x[1])
    print(f"Líneas analizadas: {total}")
    for clase, n in top:
        if n:
            print(f"  {clase}: {n}")
    print(f"Reporte: {analisis}")
    print(f"Resumen JSON: {resumen_path}")
    print(f"Manifiesto: {manifiesto}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
