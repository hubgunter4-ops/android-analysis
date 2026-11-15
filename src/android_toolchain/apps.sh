#!/usr/bin/env bash
#
# Apps, uso, conexiones y datos — listado de apps, uso en primer plano,
# conexiones de red y desglose de datos por app, más las acciones
# solicitadas por cada app y el árbol de procesos (de quién hereda
# cada proceso). Solo sobre un dispositivo de laboratorio autorizado
# y con confirmación explícita.
#
# Solo lectura: no instala, no ejecuta ni modifica nada en el
# dispositivo. No se recoge contenido ni cargas útiles: solo
# metadatos (paquetes y UID, tiempos de uso, extremos IP:puerto,
# contadores de bytes, servicios/trabajos/alarmas/wakelocks y
# PID/PPID). La evidencia queda fuera del árbol del proyecto, con
# manifiesto y SHA-256 por fuente. El análisis y la clasificación
# se hacen en local con python3; el crudo de dumpsys queda en los
# archivos de fuente, el informe solo lleva conteos y muestras.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/android_toolchain/scope.sh
source "$SCRIPT_DIR/scope.sh"

APPS_VERSION="2.1.0"
OUT_DIR="${OUT_DIR:-$HOME/security-tools/apps}"
SERIAL=""
SCOPE_FILE=""
TODAS=0
DRY_RUN=0
PLAN_JSON=0
CONFIRM=0
PM_VERSIONCODE=0
PM_UID=0

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 2
}

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

usage() {
    cat <<'EOF'
Uso: apps.sh [opciones]

  --serial SERIAL        Serial del dispositivo (verificado en `adb devices`).
                         Sin serial se exige exactamente un dispositivo `device`.
  --todas                Incluir también las apps del sistema (por defecto solo
                         apps de terceros, `pm list packages -3`).
  --out-dir PATH         Directorio base de evidencia (default: $HOME/security-tools/apps).
                         Cada ejecución crea <out-dir>/APPS-AAAAMMDD-HHMMSS_<serial>/.
  --scope-file PATH      Archivo de alcance de laboratorio (allowlist).
                         Default: $HOME/security-tools/scope si existe.
  --dry-run              Muestra el plan; no llama a adb ni crea directorios.
  --plan-json            Emite el plan como JSON y no ejecuta la recogida.
  --confirm              Confirmación explícita para una recogida real.
                         Sin --dry-run ni --confirm la recogida se rechaza.
  -h, --help             Muestra esta ayuda.

Ejemplos:
  ./src/android_toolchain/apps.sh --dry-run
  ./src/android_toolchain/apps.sh --dry-run --serial emulator-5554 --todas
  ./src/android_toolchain/apps.sh --plan-json
  ./src/android_toolchain/apps.sh --serial emulator-5554 --confirm
  ./src/android_toolchain/apps.sh --serial emulator-5554 --todas --confirm
EOF
}

validate_path() {
    local path="$1"
    [[ "$path" =~ ^[A-Za-z0-9_./:@+,-]+$ ]] || fail "ruta no válida; usa solo caracteres de ruta seguros"
    local part
    IFS='/' read -r -a path_parts <<< "$path"
    for part in "${path_parts[@]}"; do
        [[ "$part" != .. ]] || fail "ruta con traversal no permitida"
    done
    [[ "$path" != / ]] || fail "no se permite usar la raíz como directorio de evidencia"
}

validate_serial() {
    [[ -z "$SERIAL" || "$SERIAL" =~ ^[A-Za-z0-9._:-]+$ ]] || fail "serial no válido; usa solo letras, dígitos, ., _, - y :"
}

# argv base de adb, sin shell: serial opcional.
adb_args() {
    if [[ -n "$SERIAL" ]]; then printf '%s\n' "adb" "-s" "$SERIAL"; else printf '%s\n' "adb"; fi
}

# Fuentes en orden de recogida. apps-sistema solo se añade con --todas.
base_sources() {
    printf 'apps-terceros\n'
    (( TODAS )) && printf 'apps-sistema\n'
    printf 'uso\nconexiones\ndatos\nacciones-servicios\nacciones-trabajos\nacciones-alarmas\nacciones-wakelocks\nprocesos\n'
}

# Nombre de archivo para cada fuente.
file_for_source() {
    case "$1" in
        apps-terceros) printf '01-apps-terceros.txt' ;;
        apps-sistema) printf '02-apps-sistema.txt' ;;
        uso) printf '03-uso.txt' ;;
        conexiones) printf '04-conexiones.txt' ;;
        datos) printf '05-datos.txt' ;;
        acciones-servicios) printf '06-servicios.txt' ;;
        acciones-trabajos) printf '07-trabajos.txt' ;;
        acciones-alarmas) printf '08-alarmas.txt' ;;
        acciones-wakelocks) printf '09-wakelocks.txt' ;;
        procesos) printf '10-procesos.txt' ;;
    esac
}

# Descripción legible de cada fuente.
describe_source() {
    case "$1" in
        apps-terceros) printf 'Apps de terceros con UID (pm list packages -3 -U)' ;;
        apps-sistema) printf 'Apps del sistema con UID (pm list packages -s -U)' ;;
        uso) printf 'Uso en primer plano por app (dumpsys usagestats)' ;;
        conexiones) printf 'Conexiones TCP/UDP por UID (/proc/net/tcp, tcp6, udp, udp6)' ;;
        datos) printf 'Contadores de bytes por UID y red (dumpsys netstats)' ;;
        acciones-servicios) printf 'Servicios en ejecución por app (dumpsys activity services)' ;;
        acciones-trabajos) printf 'Trabajos programados por app (dumpsys jobscheduler)' ;;
        acciones-alarmas) printf 'Alarmas programadas por app (dumpsys alarm)' ;;
        acciones-wakelocks) printf 'Wakelocks retenidos por app (dumpsys power)' ;;
        procesos) printf 'Árbol de procesos PID/PPID (ps -A -o PID,PPID,NAME)' ;;
    esac
}

# Comando adb de cada fuente, impreso como una línea (forma preferida;
# pm y ps tienen fallback si la forma preferida no existe).
command_for_source() {
    local -a base
    mapfile -t base < <(adb_args)
    case "$1" in
        apps-terceros) printf '%q ' "${base[@]}" shell pm list packages --show-versioncode -3 -U; printf '(fallback: sin --show-versioncode; luego sin -U)\n' ;;
        apps-sistema) printf '%q ' "${base[@]}" shell pm list packages --show-versioncode -s -U; printf '(fallback: sin --show-versioncode; luego sin -U)\n' ;;
        uso) printf '%q ' "${base[@]}" shell dumpsys usagestats; printf '\n' ;;
        conexiones)
            printf '%q ' "${base[@]}" shell cat /proc/net/tcp; printf '; '
            printf '%q ' "${base[@]}" shell cat /proc/net/tcp6; printf '; '
            printf '%q ' "${base[@]}" shell cat /proc/net/udp; printf '; '
            printf '%q ' "${base[@]}" shell cat /proc/net/udp6; printf '\n'
            ;;
        datos) printf '%q ' "${base[@]}" shell dumpsys netstats; printf '\n' ;;
        acciones-servicios) printf '%q ' "${base[@]}" shell dumpsys activity services; printf '\n' ;;
        acciones-trabajos) printf '%q ' "${base[@]}" shell dumpsys jobscheduler; printf '\n' ;;
        acciones-alarmas) printf '%q ' "${base[@]}" shell dumpsys alarm; printf '\n' ;;
        acciones-wakelocks) printf '%q ' "${base[@]}" shell dumpsys power; printf '\n' ;;
        procesos) printf '%q ' "${base[@]}" shell ps -A -o PID,PPID,NAME; printf '(fallback: ps -A)\n' ;;
    esac
}

# Recoge una fuente y registra su resultado en los arrays globales.
# Un fallo en una fuente no aborta el resto: se anota en el manifiesto
# y el informe dice "sin datos" para esa fuente.
declare -a DONE_SOURCES=() DONE_FILES=() DONE_CODES=() DONE_DESCS=() DONE_CMDS=()
run_source() {
    local source="$1" file="$2"
    local -a base
    mapfile -t base < <(adb_args)
    local code=0 cmd=""
    log "recogiendo $source -> $(basename "$file")"
    case "$source" in
        apps-terceros|apps-sistema)
            local flag="-3"
            [[ "$source" == apps-sistema ]] && flag="-s"
            local tmp
            tmp="$(mktemp --tmpdir apps-pm.XXXXXX)"
            chmod 0600 "$tmp"
            # Forma preferida: versionCode + UID. Si el pm del
            # dispositivo no la soporta, se degrada sin abortar.
            cmd="pm list packages --show-versioncode $flag -U"
            if "${base[@]}" shell pm list packages --show-versioncode "$flag" -U >"$tmp" 2>"$file.err" && [[ -s "$tmp" ]]; then
                PM_VERSIONCODE=1
                PM_UID=1
                cp "$tmp" "$file"
            else
                cmd="pm list packages $flag -U"
                if "${base[@]}" shell pm list packages "$flag" -U >"$tmp" 2>"$file.err" && [[ -s "$tmp" ]]; then
                    PM_UID=1
                    cp "$tmp" "$file"
                else
                    cmd="pm list packages $flag"
                    if "${base[@]}" shell pm list packages "$flag" >"$file" 2>"$file.err"; then
                        code=0
                        log "ADVERTENCIA: pm sin -U en este dispositivo; conexiones y datos no se podrán atribuir por app"
                    else
                        code=$?
                    fi
                fi
            fi
            rm -f "$tmp"
            ;;
        uso)
            cmd="dumpsys usagestats"
            if "${base[@]}" shell dumpsys usagestats >"$file" 2>"$file.err"; then code=0; else code=$?; fi
            ;;
        conexiones)
            cmd="cat /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6"
            {
                local proc
                for proc in tcp tcp6 udp udp6; do
                    printf '== /proc/net/%s ==\n' "$proc"
                    if ! "${base[@]}" shell cat "/proc/net/$proc" 2>>"$file.err"; then
                        printf '(sin /proc/net/%s o sin permiso)\n' "$proc"
                        code=1
                    fi
                done
            } >"$file" 2>>"$file.err"
            ;;
        datos)
            cmd="dumpsys netstats"
            if "${base[@]}" shell dumpsys netstats >"$file" 2>"$file.err"; then code=0; else code=$?; fi
            ;;
        acciones-servicios)
            cmd="dumpsys activity services"
            if "${base[@]}" shell dumpsys activity services >"$file" 2>"$file.err"; then code=0; else code=$?; fi
            ;;
        acciones-trabajos)
            cmd="dumpsys jobscheduler"
            if "${base[@]}" shell dumpsys jobscheduler >"$file" 2>"$file.err"; then code=0; else code=$?; fi
            ;;
        acciones-alarmas)
            cmd="dumpsys alarm"
            if "${base[@]}" shell dumpsys alarm >"$file" 2>"$file.err"; then code=0; else code=$?; fi
            ;;
        acciones-wakelocks)
            cmd="dumpsys power"
            if "${base[@]}" shell dumpsys power >"$file" 2>"$file.err"; then code=0; else code=$?; fi
            ;;
        procesos)
            local tmp
            tmp="$(mktemp --tmpdir apps-ps.XXXXXX)"
            chmod 0600 "$tmp"
            cmd="ps -A -o PID,PPID,NAME"
            if "${base[@]}" shell ps -A -o PID,PPID,NAME >"$tmp" 2>"$file.err" && [[ -s "$tmp" ]]; then
                { printf '# forma: ps -A -o PID,PPID,NAME\n'; cat "$tmp"; } >"$file"
            else
                cmd="ps -A"
                if "${base[@]}" shell ps -A >"$tmp" 2>>"$file.err" && [[ -s "$tmp" ]]; then
                    { printf '# forma: ps -A (fallback; sin -o)\n'; cat "$tmp"; } >"$file"
                    code=0
                else
                    code=$?
                    printf '# ps falló en ambas formas\n' >"$file"
                fi
            fi
            rm -f "$tmp"
            ;;
    esac
    if (( code != 0 )); then
        log "ADVERTENCIA: $source terminó con código $code; revisa $file.err"
    fi
    DONE_SOURCES+=("$source")
    DONE_FILES+=("$file")
    DONE_CODES+=("$code")
    DONE_DESCS+=("$(describe_source "$source")")
    DONE_CMDS+=("$cmd")
}

print_plan() {
    local source file
    printf 'PLAN DE APPS ADB (dry-run, sin cambios)\n'
    printf 'Versión: %s | serial: %s | sistema: %s | salida: %s\n' \
        "$APPS_VERSION" "${SERIAL:-<único dispositivo>}" \
        "$([[ $TODAS -eq 1 ]] && echo sí || echo no)" "$OUT_DIR"
    while IFS= read -r source; do
        file="$(file_for_source "$source")"
        printf '+ %s> %s\n' "$(command_for_source "$source")" "$file"
    done < <(base_sources)
    printf '+ análisis local (python3) -> APPS.txt + resumen.json\n'
    printf 'Manifiesto: MANIFIESTO.txt (comando, código, bytes y SHA-256 por fuente)\n'
}

print_plan_json() {
    local source file first=1
    printf '{\n'
    printf '  "version": "%s",\n' "$APPS_VERSION"
    printf '  "serial": "%s",\n' "$SERIAL"
    printf '  "todas": %s,\n' "$([[ $TODAS -eq 1 ]] && echo true || echo false)"
    printf '  "out_dir": "%s",\n' "$OUT_DIR"
    printf '  "dry_run": %s,\n' "$([[ $DRY_RUN -eq 1 ]] && echo true || echo false)"
    printf '  "sources": ['
    while IFS= read -r source; do
        (( first )) && first=0 || printf ', '
        printf '"%s"' "$source"
    done < <(base_sources)
    printf '],\n  "files": [\n'
    first=1
    while IFS= read -r source; do
        file="$(file_for_source "$source")"
        (( first )) && first=0 || printf ',\n'
        printf '    {"source": "%s", "description": "%s", "file": "%s", "command": "%s"}' \
            "$source" "$(describe_source "$source")" "$file" "$(command_for_source "$source" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/ *$//')"
    done < <(base_sources)
    printf '\n  ],\n  "outputs": ["APPS.txt", "resumen.json"]\n}\n'
}

check_device() {
    command -v adb >/dev/null 2>&1 || fail "adb no está instalado; instala android-tools-adb"
    local devices
    devices="$(adb devices)"
    if [[ -n "$SERIAL" ]]; then
        awk -v s="$SERIAL" '$1 == s && $2 == "device" { found = 1 } END { exit !found }' <<<"$devices" \
            || fail "el serial $SERIAL no aparece como 'device' en adb devices; verifica el serial y la autorización USB"
    else
        local count
        count="$(awk '$2 == "device" { n++ } END { print n + 0 }' <<<"$devices")"
        [[ "$count" -eq 1 ]] || fail "se esperaba exactamente un dispositivo 'device' en adb devices; hay $count (indica --serial)"
    fi
}

collect() {
    command -v python3 >/dev/null 2>&1 || fail "python3 no está instalado; el análisis local lo necesita"
    check_device
    umask 077
    local stamp safe_serial run_dir
    stamp="$(date -u +%Y%m%d-%H%M%S)"
    safe_serial="${SERIAL:-sin-serial}"
    safe_serial="${safe_serial//:/_}"
    run_dir="$OUT_DIR/APPS-${stamp}_${safe_serial}"
    mkdir -p "$run_dir"
    chmod 0700 "$run_dir"
    log "evidencia en $run_dir (0700; material sensible)"

    local source file
    while IFS= read -r source; do
        file="$run_dir/$(file_for_source "$source")"
        run_source "$source" "$file"
    done < <(base_sources)

    # Análisis y clasificación en local: lee los archivos de fuente y
    # escribe APPS.txt (informe) y resumen.json (máquina).
    local code=0
    if ! python3 - "$run_dir" "${SERIAL:-<único dispositivo>}" "$APPS_VERSION" \
            "$(scope_status "$SCOPE_FILE")" \
            "$([[ $TODAS -eq 1 ]] && echo 1 || echo 0)" \
            "$PM_VERSIONCODE" "$PM_UID" <<'PYEOF'
import ipaddress
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

run_dir = Path(sys.argv[1])
serial = sys.argv[2]
version = sys.argv[3]
alcance = sys.argv[4]
todas = sys.argv[5] == "1"
pm_versioncode = sys.argv[6] == "1"
pm_uid = sys.argv[7] == "1"

ESTADOS_TCP = {
    "01": "ESTABLISHED", "02": "SYN_SENT", "03": "SYN_RECV",
    "04": "FIN_WAIT1", "05": "FIN_WAIT2", "06": "TIME_WAIT",
    "07": "CLOSE", "08": "CLOSE_WAIT", "09": "LAST_ACK",
    "0A": "LISTEN", "0B": "CLOSING",
}
ZYGOTE = {"zygote", "zygote64", "zygote32"}
MAX_MUESTRAS = 5


def leer(nombre):
    p = run_dir / nombre
    return p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""


def formato_bytes(n):
    n = float(n)
    for unidad in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unidad == "TB":
            return f"{n:.0f} {unidad}" if unidad == "B" else f"{n:.1f} {unidad}"
        n /= 1024.0
    return f"{n:.1f} TB"


def formato_duracion(seg):
    if seg is None:
        return "—"
    h, resto = divmod(int(seg), 3600)
    m, s = divmod(resto, 60)
    if h:
        return f"{h}h {m}m {s}s"
    if m:
        return f"{m}m {s}s"
    return f"{s}s"


def parse_duracion(valor):
    """ms en época, segundos con sufijo (1h 23m 45s) o milisegundos."""
    valor = valor.strip().strip('"')
    if re.fullmatch(r"\d+", valor):
        return int(valor) // 1000
    total = 0
    for num, unidad in re.findall(r"(\d+)\s*(h|ms|m|s)", valor):
        if unidad == "h":
            total += int(num) * 3600
        elif unidad == "m":
            total += int(num) * 60
        elif unidad == "s":
            total += int(num)
        elif unidad == "ms":
            total += int(num) // 1000
    return total if total else None


def parse_fecha(valor):
    valor = valor.strip().strip('"')
    if re.fullmatch(r"\d{10,}", valor):
        ms = int(valor)
        sec = ms // 1000 if len(valor) >= 13 else ms
        return datetime.fromtimestamp(sec, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    return valor or None


def parse_fecha_clave(valor):
    """Clave de ordenación para último uso: época si es número, si no la cadena."""
    valor = valor.strip().strip('"')
    if re.fullmatch(r"\d{10,}", valor):
        ms = int(valor)
        return ms // 1000 if len(valor) >= 13 else ms
    return valor


# ---------- apps y UID ----------
paquetes = {}   # pkg -> {uid, sistema, version_code}
uid_a_paquete = {}

for nombre, sistema in (("01-apps-terceros.txt", False), ("02-apps-sistema.txt", True)):
    for linea in leer(nombre).splitlines():
        m = re.match(r"package:(\S+)(?:\s+versionCode:(\d+))?(?:\s+uid:(\d+))?", linea)
        if not m:
            continue
        pkg, vc, uid = m.group(1), m.group(2), m.group(3)
        paquetes[pkg] = {
            "uid": int(uid) if uid else None,
            "sistema": sistema,
            "version_code": int(vc) if vc else None,
        }
        if uid:
            uid_a_paquete[int(uid)] = pkg

# ---------- uso (dumpsys usagestats) ----------
uso = {}  # pkg -> {segundos, ultimo_uso, _clave}
actual = None
for linea in leer("03-uso.txt").splitlines():
    m = re.match(r"\s*package[:=]\s*([\w.]+)", linea)
    if m:
        actual = m.group(1)
        uso.setdefault(actual, {"segundos": None, "ultimo_uso": None, "_clave": 0})
        continue
    if actual is None:
        continue
    m = re.search(r"lastTimeUsed[:=]\s*\"?([^\s\"]+)\"?", linea)
    if m:
        fecha = parse_fecha(m.group(1))
        clave = parse_fecha_clave(m.group(1))
        if fecha and (uso[actual]["ultimo_uso"] is None
                      or (isinstance(clave, int) and clave >= uso[actual]["_clave"])):
            uso[actual]["ultimo_uso"] = fecha
            uso[actual]["_clave"] = clave if isinstance(clave, int) else uso[actual]["_clave"]
    m = re.search(r"totalTimeInForeground[:=]\s*\"?([^\"]+)\"?", linea)
    if m:
        seg = parse_duracion(m.group(1))
        if seg is not None and (uso[actual]["segundos"] is None or seg > uso[actual]["segundos"]):
            uso[actual]["segundos"] = seg

# ---------- conexiones (/proc/net/*) ----------
def decodificar_direccion(hexaddr, v6):
    ip_hex, puerto_hex = hexaddr.rsplit(":", 1)
    puerto = int(puerto_hex, 16)
    crudo = bytes.fromhex(ip_hex)
    if v6:
        reordenado = b"".join(crudo[i:i + 4][::-1] for i in range(0, 16, 4))
        ip = str(ipaddress.IPv6Address(reordenado))
        return f"[{ip}]:{puerto}"
    ip = str(ipaddress.IPv4Address(crudo[::-1]))
    return f"{ip}:{puerto}"


conexiones = []  # {proto, local, remoto, estado, uid}
seccion = None
for linea in leer("04-conexiones.txt").splitlines():
    m = re.match(r"== /proc/net/(tcp6?|udp6?) ==", linea)
    if m:
        seccion = m.group(1)
        continue
    campos = linea.split()
    if seccion and len(campos) >= 10 and campos[0].rstrip(":").isdigit():
        proto = "tcp" if seccion.startswith("tcp") else "udp"
        v6 = seccion.endswith("6")
        try:
            local = decodificar_direccion(campos[1], v6)
            remoto = decodificar_direccion(campos[2], v6)
            uid = int(campos[7])
        except (ValueError, IndexError):
            continue
        estado_hex = campos[3]
        estado = ESTADOS_TCP.get(estado_hex, estado_hex) if proto == "tcp" else "UDP"
        conexiones.append({"proto": proto, "local": local, "remoto": remoto,
                           "estado": estado, "uid": uid})

conexiones_por_paquete = {}
conexiones_sin_app = []
for c in conexiones:
    pkg = uid_a_paquete.get(c["uid"])
    if pkg:
        conexiones_por_paquete.setdefault(pkg, []).append(c)
    else:
        conexiones_sin_app.append(c)

# ---------- datos (dumpsys netstats) ----------
# Formato tolerante: bloques `iface=... ident=[{type=MOBILE|WIFI, ...}]`
# con `UID <n> set=...` y líneas `rxBytes=/rb=` y `txBytes=/tb=`.
datos = {}  # uid -> {MOBILE: {rx, tx}, WIFI: {rx, tx}}
tipo_actual = None
uid_actual = None
for linea in leer("05-datos.txt").splitlines():
    if "iface=" in linea:
        m = re.search(r"\btype=(MOBILE|WIFI)\b", linea)
        tipo_actual = m.group(1) if m else None
        uid_actual = None
        continue
    m = re.match(r"\s*UID\s+(\d+)\b", linea) or re.search(r"\buid=(\d+)\b", linea)
    if m:
        uid_actual = int(m.group(1))
        continue
    if uid_actual is None or tipo_actual is None:
        continue
    mrx = re.search(r"(?:rxBytes|rb)=(\d+)", linea)
    mtx = re.search(r"(?:txBytes|tb)=(\d+)", linea)
    if mrx or mtx:
        d = datos.setdefault(uid_actual, {"MOBILE": {"rx": 0, "tx": 0},
                                          "WIFI": {"rx": 0, "tx": 0}})
        if mrx:
            d[tipo_actual]["rx"] += int(mrx.group(1))
        if mtx:
            d[tipo_actual]["tx"] += int(mtx.group(1))

# ---------- acciones solicitadas ----------
def muestras(d, pkg, texto):
    lista = d.setdefault(pkg, [])
    if len(lista) < MAX_MUESTRAS and texto:
        lista.append(texto[:200])

# Servicios: líneas `ServiceRecord{...}`. En el volcado real el
# componente va dentro de las llaves
# (`ServiceRecord{abc123 u0 com.ejemplo.app/.Servicio}`); en
# algunas versiones va fuera, tras `}`. Se busca en ambos sitios.
servicios = {}
for linea in leer("06-servicios.txt").splitlines():
    m = re.search(r"ServiceRecord\{([^}]*)\}(.*)$", linea)
    if not m:
        continue
    mm = re.search(r"([A-Za-z][\w.]*)/", m.group(1)) or \
        re.search(r"([A-Za-z][\w.]*)/", m.group(2))
    if mm and mm.group(1) in paquetes:
        muestras(servicios, mm.group(1), linea.strip())

# Trabajos: bloques `JOB #...`; el paquete sale del componente
# `com.ejemplo.app/.Servicio` o del usuario u0aNNN (uid = 10000 + NNN).
trabajos = {}
bloque = None


def procesar_bloque_trabajo(bloque):
    texto = "\n".join(bloque)
    pkg = None
    m = re.search(r"([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)/", texto)
    if m:
        pkg = m.group(1)
    else:
        m = re.search(r"u0a(\d+)", bloque[0])
        if m:
            pkg = uid_a_paquete.get(10000 + int(m.group(1)))
    if pkg and pkg in paquetes:
        muestras(trabajos, pkg, bloque[0].strip())


for linea in leer("07-trabajos.txt").splitlines():
    if re.search(r"\bJOB\s+#", linea):
        if bloque:
            procesar_bloque_trabajo(bloque)
        bloque = [linea]
        continue
    if bloque is not None:
        if linea and not linea[0].isspace():
            procesar_bloque_trabajo(bloque)
            bloque = None
            continue
        bloque.append(linea)
if bloque:
    procesar_bloque_trabajo(bloque)

# Alarmas: bloques `Alarm{...}`. El bloque termina en la siguiente
# línea `Alarm{` o en una línea sin sangría (nueva sección); el
# paquete se busca primero en la propia línea de la alarma y luego
# en el resto del bloque (línea `tag=`).
alarmas = {}
lineas_alarma = leer("08-alarmas.txt").splitlines()
orden_paquetes = sorted(paquetes, key=len, reverse=True)
i = 0
while i < len(lineas_alarma):
    linea = lineas_alarma[i]
    if "Alarm{" in linea:
        bloque = [linea]
        j = i + 1
        while j < len(lineas_alarma) and j < i + 6:
            sig = lineas_alarma[j]
            if "Alarm{" in sig or (sig and not sig[0].isspace()):
                break
            bloque.append(sig)
            j += 1
        texto = "\n".join(bloque)
        pkg = next((p for p in orden_paquetes if p in linea), None) or \
            next((p for p in orden_paquetes if p in texto), None)
        if pkg:
            muestras(alarmas, pkg, linea.strip())
        i = j
    else:
        i += 1

# Wakelocks: sección `Wake Locks:` de dumpsys power; líneas con
# `uid=<n>`; la muestra es el nombre entre comillas si lo hay.
wakelocks = {}
en_seccion = False
for linea in leer("09-wakelocks.txt").splitlines():
    if re.match(r"\s*Wake Locks:", linea):
        en_seccion = True
        continue
    if en_seccion:
        if re.match(r"  [A-Z][A-Za-z ]*:", linea):
            en_seccion = False
            continue
        m = re.search(r"uid=(\d+)", linea)
        if m:
            pkg = uid_a_paquete.get(int(m.group(1)))
            if pkg:
                nombre = re.search(r"'([^']+)'", linea)
                muestras(wakelocks, pkg,
                         nombre.group(1) if nombre else linea.strip())

# ---------- procesos y árbol ----------
def parsear_ps(texto):
    lineas = [l for l in texto.splitlines() if l.strip()]
    forma_o = texto.startswith("# forma: ps -A -o")
    procesos = []
    for linea in lineas:
        if linea.startswith("#"):
            continue
        if re.match(r"\s*PID\s+PPID\s+NAME", linea) or linea.strip().startswith("USER"):
            continue
        campos = linea.split()
        try:
            if forma_o:
                if len(campos) < 3 or not campos[0].isdigit():
                    continue
                pid, ppid = int(campos[0]), int(campos[1])
                nombre = " ".join(campos[2:])
            else:
                if len(campos) < 9 or not campos[1].isdigit():
                    continue
                pid, ppid = int(campos[1]), int(campos[2])
                nombre = campos[-1]
        except ValueError:
            continue
        procesos.append({"pid": pid, "ppid": ppid, "nombre": nombre})
    return procesos


procesos = parsear_ps(leer("10-procesos.txt"))
nombre_por_pid = {p["pid"]: p["nombre"] for p in procesos}
hijos = {}
for p in procesos:
    hijos.setdefault(p["ppid"], []).append(p)


def es_inusual(p):
    if p["ppid"] == 0 or p["pid"] <= 2:
        return False
    if p["nombre"].startswith("["):
        return False
    padre = nombre_por_pid.get(p["ppid"], "")
    return padre not in ZYGOTE and padre != "init"


herencia_inusual = [p for p in procesos if es_inusual(p)]


def seccion_arbol():
    out = []
    if not procesos:
        return ["sin datos de procesos (ps falló o salió vacío)"]
    init = next((p for p in procesos if p["pid"] == 1), None)
    if init is None:
        return ["sin proceso init (PID 1) en la salida de ps"]

    def rama(pid, prefijo, max_hijos=40):
        ninos = sorted(hijos.get(pid, []), key=lambda p: p["nombre"])
        mostrados = ninos[:max_hijos]
        for i, c in enumerate(mostrados):
            ultimo = i == len(mostrados) - 1
            conector = "└─ " if ultimo else "├─ "
            out.append(f"{prefijo}{conector}{c['nombre']} ({c['pid']})")
            # Se expande el padre si es zygote, si el hijo es inusual
            # o si alguno de sus hijos es inusual (para ver de quién
            # hereda un proceso con padre raro).
            if (c["nombre"] in ZYGOTE or es_inusual(c)
                    or any(es_inusual(h) for h in hijos.get(c["pid"], []))):
                rama(c["pid"], prefijo + ("   " if ultimo else "│  "), max_hijos)
        if len(ninos) > max_hijos:
            out.append(f"{prefijo}└─ ... y {len(ninos) - max_hijos} más")

    out.append(f"{init['nombre']} ({init['pid']})")
    rama(1, "")
    return out


# ---------- informe ----------
fecha = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
sin_datos = []
if not any(u["segundos"] is not None or u["ultimo_uso"] for u in uso.values()):
    sin_datos.append("uso")
if not conexiones and not leer("04-conexiones.txt").strip():
    sin_datos.append("conexiones")
if not datos:
    sin_datos.append("datos")
for clave, fuente, nombre in (("servicios", "06-servicios.txt", "servicios"),
                              ("trabajos", "07-trabajos.txt", "trabajos"),
                              ("alarmas", "08-alarmas.txt", "alarmas"),
                              ("wakelocks", "09-wakelocks.txt", "wakelocks")):
    if not leer(fuente).strip():
        sin_datos.append(clave)
if not procesos:
    sin_datos.append("procesos")

apps_orden = sorted(paquetes, key=lambda p: (paquetes[p]["sistema"], p))
tot_rx_movil = sum(d["MOBILE"]["rx"] for d in datos.values())
tot_tx_movil = sum(d["MOBILE"]["tx"] for d in datos.values())
tot_rx_wifi = sum(d["WIFI"]["rx"] for d in datos.values())
tot_tx_wifi = sum(d["WIFI"]["tx"] for d in datos.values())

registros = []
for pkg in apps_orden:
    info = paquetes[pkg]
    uid = info["uid"]
    d = datos.get(uid, {"MOBILE": {"rx": 0, "tx": 0}, "WIFI": {"rx": 0, "tx": 0}}) if uid else \
        {"MOBILE": {"rx": 0, "tx": 0}, "WIFI": {"rx": 0, "tx": 0}}
    u = uso.get(pkg, {"segundos": None, "ultimo_uso": None})
    conns = conexiones_por_paquete.get(pkg, [])
    procs = [p for p in procesos
             if p["nombre"] == pkg or p["nombre"].startswith(pkg + ":")]
    principal = next((p for p in procs if p["nombre"] == pkg), procs[0] if procs else None)
    registros.append({
        "paquete": pkg,
        "uid": uid,
        "sistema": info["sistema"],
        "version_code": info["version_code"],
        "uso_segundos": u["segundos"],
        "ultimo_uso": u["ultimo_uso"],
        "conexiones": [{"proto": c["proto"], "local": c["local"],
                        "remoto": c["remoto"], "estado": c["estado"]} for c in conns],
        "datos": {"movil": d["MOBILE"], "wifi": d["WIFI"]},
        "acciones": {
            "servicios": len(servicios.get(pkg, [])),
            "trabajos": len(trabajos.get(pkg, [])),
            "alarmas": len(alarmas.get(pkg, [])),
            "wakelocks": len(wakelocks.get(pkg, [])),
            "muestras": {
                "servicios": servicios.get(pkg, []),
                "trabajos": trabajos.get(pkg, []),
                "alarmas": alarmas.get(pkg, []),
                "wakelocks": wakelocks.get(pkg, []),
            },
        },
        "proceso": ({
            "pid": principal["pid"],
            "ppid": principal["ppid"],
            "padre": nombre_por_pid.get(principal["ppid"], "desconocido"),
            "n_procesos": len(procs),
        } if principal else None),
    })

lineas = []
lineas.append("APPS, USO, CONEXIONES Y DATOS")
lineas.append(f"versión: {version}")
lineas.append(f"fecha: {fecha}")
lineas.append(f"serial: {serial}")
lineas.append(f"alcance: {alcance}")
lineas.append(f"sistema incluido (--todas): {'sí' if todas else 'no'}")
lineas.append(f"versionCode disponible: {'sí' if pm_versioncode else 'no (pm sin --show-versioncode)'}")
lineas.append(f"UID disponible: {'sí' if pm_uid else 'no (pm sin -U; conexiones y datos sin atribuir)'}")
lineas.append("")
lineas.append("RESUMEN")
n_terceros = sum(1 for p in paquetes.values() if not p["sistema"])
n_sistema = sum(1 for p in paquetes.values() if p["sistema"])
lineas.append(f"  apps de terceros: {n_terceros}")
if todas:
    lineas.append(f"  apps del sistema: {n_sistema}")
lineas.append(f"  conexiones activas: {len(conexiones)} "
              f"(TCP {sum(1 for c in conexiones if c['proto'] == 'tcp')}, "
              f"UDP {sum(1 for c in conexiones if c['proto'] == 'udp')})")
lineas.append(f"  datos totales: móvil rx {formato_bytes(tot_rx_movil)} / "
              f"tx {formato_bytes(tot_tx_movil)}; wifi rx {formato_bytes(tot_rx_wifi)} / "
              f"tx {formato_bytes(tot_tx_wifi)}")
lineas.append(f"  procesos: {len(procesos)} (herencia inusual: {len(herencia_inusual)})")
if sin_datos:
    lineas.append(f"  sin datos: {', '.join(sin_datos)}")
lineas.append("")
lineas.append("TABLA POR APP")
lineas.append(f"{'PAQUETE':<38} {'UID':>7} {'SIST':>4} {'USO':>9} {'ÚLTIMO USO':<16} "
              f"{'CONN':>4} {'DATOS':>10} {'PID':>7} {'PPID':>7} {'HEREDA DE':<12} "
              f"{'SERV':>4} {'TRAB':>4} {'ALRM':>4} {'WAKE':>4}")
for r in registros:
    total_datos = (r["datos"]["movil"]["rx"] + r["datos"]["movil"]["tx"]
                   + r["datos"]["wifi"]["rx"] + r["datos"]["wifi"]["tx"])
    proc = r["proceso"]
    lineas.append(
        f"{r['paquete'][:38]:<38} "
        f"{str(r['uid'] if r['uid'] is not None else '—'):>7} "
        f"{('sí' if r['sistema'] else 'no'):>4} "
        f"{formato_duracion(r['uso_segundos']):>9} "
        f"{(r['ultimo_uso'] or '—')[:16]:<16} "
        f"{len(r['conexiones']):>4} "
        f"{formato_bytes(total_datos):>10} "
        f"{str(proc['pid'] if proc else '—'):>7} "
        f"{str(proc['ppid'] if proc else '—'):>7} "
        f"{(proc['padre'][:12] if proc else '—'):<12} "
        f"{r['acciones']['servicios']:>4} "
        f"{r['acciones']['trabajos']:>4} "
        f"{r['acciones']['alarmas']:>4} "
        f"{r['acciones']['wakelocks']:>4}")
lineas.append("")
lineas.append("DESGLOSE DE DATOS POR APP (bytes)")
lineas.append(f"{'PAQUETE':<38} {'RX MÓVIL':>12} {'TX MÓVIL':>12} "
              f"{'RX WIFI':>12} {'TX WIFI':>12} {'TOTAL':>12}")
for r in registros:
    d = r["datos"]
    total = d["movil"]["rx"] + d["movil"]["tx"] + d["wifi"]["rx"] + d["wifi"]["tx"]
    lineas.append(f"{r['paquete'][:38]:<38} {d['movil']['rx']:>12} {d['movil']['tx']:>12} "
                  f"{d['wifi']['rx']:>12} {d['wifi']['tx']:>12} {total:>12}")
lineas.append("")
lineas.append("ACCIONES SOLICITADAS POR APP")
hay_acciones = False
for r in registros:
    a = r["acciones"]
    if not (a["servicios"] or a["trabajos"] or a["alarmas"] or a["wakelocks"]):
        continue
    hay_acciones = True
    lineas.append(f"{r['paquete']} — servicios: {a['servicios']}, trabajos: {a['trabajos']}, "
                  f"alarmas: {a['alarmas']}, wakelocks: {a['wakelocks']}")
    for clave, etiqueta in (("servicios", "servicios"), ("trabajos", "trabajos"),
                            ("alarmas", "alarmas"), ("wakelocks", "wakelocks")):
        for muestra in a["muestras"][clave]:
            lineas.append(f"  {etiqueta}: {muestra}")
if not hay_acciones:
    lineas.append("sin acciones atribuibles a las apps listadas")
lineas.append("")
lineas.append("ÁRBOL DE PROCESOS")
lineas.extend(seccion_arbol())
lineas.append("")
if herencia_inusual:
    lineas.append("HERENCIA INUSUAL (padre distinto de init y de zygote)")
    for p in herencia_inusual:
        padre = nombre_por_pid.get(p["ppid"], "desconocido")
        lineas.append(f"  {p['nombre']} ({p['pid']}) <- {padre} ({p['ppid']})")
    lineas.append("")
if conexiones_sin_app:
    lineas.append("CONEXIONES SIN APP CONOCIDA (UID sin paquete listado)")
    for c in conexiones_sin_app[:10]:
        lineas.append(f"  {c['proto']} {c['local']} -> {c['remoto']} {c['estado']} (uid {c['uid']})")
    if len(conexiones_sin_app) > 10:
        lineas.append(f"  ... y {len(conexiones_sin_app) - 10} más")
    lineas.append("")
lineas.append("NOTAS")
lineas.append("- Solo metadatos: no se recoge contenido de apps, mensajes, "
             "archivos ni cargas útiles de red.")
if sin_datos:
    lineas.append(f"- Sin datos de: {', '.join(sin_datos)}; no es un error: "
                 "el volcado salió vacío o no se pudo interpretar en este dispositivo.")
if not todas:
    lineas.append("- Servicios, trabajos, alarmas y wakelocks de apps del sistema "
                 "no se cuentan sin --todas.")
lineas.append("- Los contadores de netstats son acumulados desde el arranque "
             "del contador, no de la última hora.")
lineas.append("- Herencia inusual excluye hilos del kernel ([...]) y PID 1 y 2; "
             "un padre distinto de init/zygote suele ser un daemon propio de la app.")

informe = run_dir / "APPS.txt"
informe.write_text("\n".join(lineas) + "\n", encoding="utf-8")

resumen = {
    "version": version,
    "fecha": fecha,
    "serial": serial,
    "todas": todas,
    "apps": registros,
    "totales": {
        "apps_terceros": n_terceros,
        "apps_sistema": n_sistema,
        "conexiones": len(conexiones),
        "conexiones_tcp": sum(1 for c in conexiones if c["proto"] == "tcp"),
        "conexiones_udp": sum(1 for c in conexiones if c["proto"] == "udp"),
        "datos": {"movil": {"rx": tot_rx_movil, "tx": tot_tx_movil},
                  "wifi": {"rx": tot_rx_wifi, "tx": tot_tx_wifi}},
        "procesos": len(procesos),
        "herencia_inusual": len(herencia_inusual),
    },
    "herencia_inusual": [
        {"pid": p["pid"], "nombre": p["nombre"], "ppid": p["ppid"],
         "padre": nombre_por_pid.get(p["ppid"], "desconocido")}
        for p in herencia_inusual
    ],
    "sin_datos": sin_datos,
}
resumen_path = run_dir / "resumen.json"
resumen_path.write_text(json.dumps(resumen, indent=2, ensure_ascii=False),
                        encoding="utf-8")

print(f"apps listadas: {len(registros)} ({n_terceros} terceros"
      + (f", {n_sistema} sistema" if todas else "") + ")")
print(f"conexiones activas: {len(conexiones)}")
print(f"procesos: {len(procesos)} (herencia inusual: {len(herencia_inusual)})")
if sin_datos:
    print(f"sin datos: {', '.join(sin_datos)}")
PYEOF
    then
        code=$?
        log "ADVERTENCIA: el análisis local falló (código $code); el crudo queda en los archivos de fuente"
    fi

    local informe="$run_dir/APPS.txt"
    local resumen_path="$run_dir/resumen.json"
    [[ -f "$informe" ]] && chmod 0600 "$informe"
    [[ -f "$resumen_path" ]] && chmod 0600 "$resumen_path"

    local manifest="$run_dir/MANIFIESTO.txt"
    {
        printf 'MANIFIESTO DE APPS ADB\n'
        printf 'versión: %s\n' "$APPS_VERSION"
        printf 'alcance: %s\n' "$(scope_status "$SCOPE_FILE")"
        printf 'fecha UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'serial: %s\n' "${SERIAL:-<único dispositivo>}"
        printf 'sistema incluido: %s\n' "$([[ $TODAS -eq 1 ]] && echo sí || echo no)"
        printf 'directorio: %s\n' "$run_dir"
        printf '\n%-18s %-6s %10s  %s\n' "fuente" "código" "bytes" "archivo (SHA-256)"
        local i bytes sha
        for i in "${!DONE_SOURCES[@]}"; do
            bytes="$(stat -c%s "${DONE_FILES[$i]}" 2>/dev/null || echo 0)"
            sha="$(sha256sum "${DONE_FILES[$i]}" 2>/dev/null | cut -d' ' -f1 || echo -)"
            printf '%-18s %-6s %10s  %s (%s)\n' "${DONE_SOURCES[$i]}" "${DONE_CODES[$i]}" "$bytes" \
                "$(basename "${DONE_FILES[$i]}")" "$sha"
            printf '  %s\n' "${DONE_DESCS[$i]}"
            printf '  comando: %s\n' "${DONE_CMDS[$i]}"
        done
        printf '\n%-18s %-6s %10s  %s\n' "salida" "código" "bytes" "archivo (SHA-256)"
        for i in "$informe" "$resumen_path"; do
            if [[ -f "$i" ]]; then
                bytes="$(stat -c%s "$i" 2>/dev/null || echo 0)"
                sha="$(sha256sum "$i" 2>/dev/null | cut -d' ' -f1 || echo -)"
                printf '%-18s %-6s %10s  %s (%s)\n' "$(basename "$i" .txt)" "-" "$bytes" "$(basename "$i")" "$sha"
            else
                printf '%-18s %-6s %10s  %s\n' "$(basename "$i" .txt)" "-" "-" "$(basename "$i") (no generado)"
            fi
        done
        printf '\nRetención: el informe contiene paquetes, UID y extremos de red; consérvalo solo según la autorización vigente.\n'
    } >"$manifest"
    chmod 0600 "$manifest"

    local warnings=0 c
    for c in "${DONE_CODES[@]}"; do (( c != 0 )) && warnings=$((warnings + 1)); done
    log "recogida completa en $run_dir"
    if (( warnings )); then
        log "ADVERTENCIAS: $warnings fuente(s) fallaron; revisa los .err y el manifiesto"
    fi
    printf 'Informe: %s\n' "$informe"
    printf 'Resumen JSON: %s\n' "$resumen_path"
    printf 'Manifiesto: %s\n' "$manifest"
}

main() {
    while (($#)); do
        case "$1" in
            --serial) (($# >= 2)) || fail "--serial requiere SERIAL"; SERIAL="$2"; shift 2 ;;
            --out-dir) (($# >= 2)) || fail "--out-dir requiere PATH"; OUT_DIR="$2"; shift 2 ;;
            --scope-file) (($# >= 2)) || fail "--scope-file requiere PATH"; SCOPE_FILE="$2"; shift 2 ;;
            --todas) TODAS=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            --plan-json) PLAN_JSON=1; shift ;;
            --confirm) CONFIRM=1; shift ;;
            -h|--help) usage; return 0 ;;
            *) fail "opción desconocida: $1" ;;
        esac
    done

    validate_serial
    scope_validate_path "$SCOPE_FILE"
    if [[ -n "$SCOPE_FILE" && ! -f "$SCOPE_FILE" ]]; then
        fail "archivo de alcance no encontrado: $SCOPE_FILE"
    fi
    SCOPE_FILE="$(scope_file_effective "$SCOPE_FILE")"
    scope_check_serial "$SCOPE_FILE" "$SERIAL"
    validate_path "$OUT_DIR"
    if [[ "$OUT_DIR" != /* ]]; then OUT_DIR="$PWD/$OUT_DIR"; fi
    OUT_DIR="$(realpath -m -- "$OUT_DIR")"

    if (( PLAN_JSON )); then print_plan_json; return 0; fi
    if (( DRY_RUN )); then print_plan; return 0; fi
    (( CONFIRM )) || fail "recogida real sin --confirm; usa --dry-run para revisar el plan y --confirm para recoger (dispositivo autorizado)"
    collect
}

main "$@"
