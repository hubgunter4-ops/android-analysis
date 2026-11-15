# Analizar trazas ADB

Analizar y clasificar trazas capturadas (y bugreports) por fuente,
severidad y clase, solo sobre material ya capturado o subido por el
operador. El análisis es de solo lectura sobre la entrada: nunca
conecta a un dispositivo salvo que se le pida explícitamente un
bugreport (`--analyze-pedir-bugreport`).

## Qué clasifica

`src/android_toolchain/analyze_traces.py` (Python, solo biblioteca
estándar) acepta una carpeta de captura
(`~/security-tools/traces/<fecha>_<serial>/`), archivos sueltos
(`.txt` o `.zip`) o un bugreport.zip:

- **Por archivo (fuente):** `01-procesos-ps-A`, `02-procesos-top`,
  `03-logcat-errores`, `04-logcat-crash`, `05-logcat-sistema`,
  `06-kernel-dmesg`, `07-kernel-anterior-pstore`, `08-fallos-dropbox`,
  y el `.txt` principal dentro de un bugreport.zip.
- **Por clase** (en orden de prioridad, la primera que casa gana):
  reinicio-energia (`2sec_reboot`, `power status Exception`,
  `RESET_REASON`, `reboot reason`, `kernel panic`, `watchdog bark`),
  crash (`FATAL EXCEPTION`, `SIGSEGV`, `has died`, `tombstone`),
  anr (`ANR`, `Application Not Responding`), memoria
  (`OutOfMemory`, `lowmemorykiller`), permisos (`SecurityException`,
  `avc: denied`), red (`connect timed out`, `SocketTimeout`),
  almacenamiento (`No space left`, `I/O error`), kernel (`BUG:`,
  `hung task`, `oops`) y proceso (`Scheduling restart`, `zygote`).
  Lo que no casa queda en `otros` (solo conteo).
- **Por severidad:** del nivel logcat cuando la línea lo trae
  (`E`/`F` alta, `W` media, resto baja); si no, de la clase
  (reinicio/crash/anr/kernel alta; memoria/permisos/red/
  almacenamiento media; proceso baja).

El reporte muestra conteos y hasta 5 muestras de una línea por clase
y archivo (`--max-muestras`, 0–50); el crudo nunca se copia al
reporte. Un bugreport.zip se extrae a un temporal (0700), se escanea
el `.txt` principal y se borra al terminar. Archivos de más de
500.000 líneas se truncan y el reporte lo indica.

## Uso

```bash
# Plan (sin cambios) y plan JSON
python3 src/android_toolchain/analyze_traces.py --dir ~/security-tools/traces/20261115-101500_emulator-5554 --dry-run
python3 src/android_toolchain/analyze_traces.py --dir ~/security-tools/traces/20261115-101500_emulator-5554 --plan-json

# Analizar una carpeta de captura
python3 src/android_toolchain/analyze_traces.py --dir ~/security-tools/traces/20261115-101500_emulator-5554

# Subir y analizar archivos sueltos (un bugreport.zip o varios .txt)
python3 src/android_toolchain/analyze_traces.py --file ~/Descargas/bugreport.zip
python3 src/android_toolchain/analyze_traces.py --file 03-logcat-errores.txt --file 06-kernel-dmesg.txt
```

Vía el instalador (`./src/no4nn.sh`), con las mismas reglas:

```bash
./src/no4nn.sh --analyze --dry-run --analyze-dir ~/security-tools/traces/20261115-101500_emulator-5554
./src/no4nn.sh --analyze --analyze-file ~/Descargas/bugreport.zip
```

En la GUI, la pestaña **ANALIZAR TRAZAS** tiene: carpeta de captura
con botón **Examinar**, archivos subidos con **Subir archivo(s)**
(`.txt` o `.zip`), y el botón **Solicitar bugreport al dispositivo**
que pide el bugreport, lo guarda y lo analiza solo (ver abajo).

## Pedir un bugreport al dispositivo

```bash
# Plan (sin cambios)
./src/no4nn.sh --analyze --analyze-pedir-bugreport --analyze-serial emulator-5554 --dry-run

# Pedirlo y analizarlo (exige --analyze-confirm; tarda unos minutos)
./src/no4nn.sh --analyze --analyze-pedir-bugreport --analyze-serial emulator-5554 --analyze-confirm
```

El pedido exige un dispositivo en estado `device` (sin `--analyze-serial`
se exige un único dispositivo), respeta el alcance de laboratorio
(`--scope-file`) y usa un timeout de 300 s (`--analyze-timeout`).
El zip se guarda en el directorio de evidencia
(`bugreport-<fecha>_<serial>.zip`) y se analiza automáticamente.
Un dispositivo `unauthorized` no puede entregar un bugreport: la
huella RSA se acepta en el teléfono.

## Evidencia

Cada análisis crea
`~/security-tools/analyses/ANALISIS-AAAAMMDD-HHMMSS_<etiqueta>/`
(0700) con `ANALISIS.txt` (resumen por clase y severidad, hallazgos
principales, muestras por archivo), `resumen.json` (mismo contenido
en JSON, para automatizar) y `MANIFIESTO.txt` (SHA-256 de las
entradas y de las salidas). Las muestras pueden contener material
sensible (rutas, paquetes, identificadores): consérvalas según la
autorización vigente y no las subas al repo.

## Límites

La clasificación es por patrones de texto: cuenta indicios, no
establece causas. Un `kernel panic` se clasifica como
reinicio-energia (por prioridad) porque un pánico reinicia el equipo.
Antes de concluir una causa, revisa las muestras y el contexto del
archivo. Si un formato de registro no casa con ningún patrón, queda
en `otros`: amplía las reglas en `analyze_traces.py` y documenta el
cambio.
