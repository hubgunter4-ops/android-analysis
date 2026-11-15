#!/usr/bin/env bash
#
# Trazas ADB — procesos, fallos/errores y registro del kernel.
# Captura solo desde un dispositivo de laboratorio autorizado, con
# confirmación explícita, y guarda cada fuente en su propio archivo
# bajo un directorio de evidencia fuera del árbol del proyecto.
#
# No conecta dispositivos automáticamente: verifica que el serial
# indicado ya aparezca como `device` en `adb devices`. No ejecuta
# ninguna aplicación objetivo ni instala nada en el dispositivo.
# Los logs pueden contener datos personales o credenciales: trátalos
# como material sensible y consérvalos solo según la autorización.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/android_toolchain/scope.sh
source "$SCRIPT_DIR/scope.sh"

TRACES_VERSION="2.1.0"
OUT_DIR="${OUT_DIR:-$HOME/security-tools/traces}"
SERIAL=""
SCOPE_FILE=""
SOURCES=""
INCLUDE_BUGREPORT=0
DRY_RUN=0
PLAN_JSON=0
CONFIRM=0

# Fuentes conocidas, en orden de captura. `bugreport` solo se añade
# con --include-bugreport: es pesado y concentra datos sensibles.
KNOWN_SOURCES=(procesos procesos-top logcat-errores logcat-crash logcat-sistema kernel-dmesg kernel-anterior fallos-dropbox bugreport)
DEFAULT_SOURCES="procesos,procesos-top,logcat-errores,logcat-crash,logcat-sistema,kernel-dmesg,kernel-anterior,fallos-dropbox"

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 2
}

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

usage() {
    cat <<'EOF'
Uso: traces.sh [opciones]

  --serial SERIAL        Serial del dispositivo (verificado en `adb devices`).
                         Sin serial se exige exactamente un dispositivo `device`.
  --out-dir PATH         Directorio base de evidencia (default: $HOME/security-tools/traces).
                         Cada captura crea <out-dir>/AAAAMMDD-HHMMSS_<serial>/.
  --sources LISTA        Fuentes separadas por coma (default: todas menos bugreport).
                         Valores: procesos, procesos-top, logcat-errores, logcat-crash,
                         logcat-sistema, kernel-dmesg, kernel-anterior, fallos-dropbox, bugreport.
  --include-bugreport    Añade `adb bugreport` (pesado y sensible; apagado por defecto).
  --dry-run              Muestra el plan; no llama a adb ni crea directorios.
  --plan-json            Emite el plan como JSON y no ejecuta la captura.
  --scope-file PATH      Archivo de alcance de laboratorio (allowlist).
                         Default: $HOME/security-tools/scope si existe.
  --confirm              Confirmación explícita para una captura real.
                         Sin --dry-run ni --confirm la captura se rechaza.
  -h, --help             Muestra esta ayuda.

Ejemplos:
  ./src/android_toolchain/traces.sh --dry-run
  ./src/android_toolchain/traces.sh --dry-run --serial emulator-5554
  ./src/android_toolchain/traces.sh --plan-json --sources procesos,kernel-dmesg
  ./src/android_toolchain/traces.sh --serial emulator-5554 --confirm
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

validate_sources() {
    local source known
    IFS=',' read -r -a wanted <<< "$SOURCES"
    for source in "${wanted[@]}"; do
        known=0
        for candidate in "${KNOWN_SOURCES[@]}"; do
            [[ "$source" == "$candidate" ]] && known=1
        done
        (( known )) || fail "fuente desconocida: $source"
    done
}

# argv base de adb, sin shell: serial opcional.
adb_args() {
    if [[ -n "$SERIAL" ]]; then printf '%s\n' "adb" "-s" "$SERIAL"; else printf '%s\n' "adb"; fi
}

# Nombre de archivo para cada fuente.
file_for_source() {
    case "$1" in
        procesos) printf '01-procesos-ps-A.txt' ;;
        procesos-top) printf '02-procesos-top.txt' ;;
        logcat-errores) printf '03-logcat-errores.txt' ;;
        logcat-crash) printf '04-logcat-crash.txt' ;;
        logcat-sistema) printf '05-logcat-sistema.txt' ;;
        kernel-dmesg) printf '06-kernel-dmesg.txt' ;;
        kernel-anterior) printf '07-kernel-anterior-pstore.txt' ;;
        fallos-dropbox) printf '08-fallos-dropbox.txt' ;;
        bugreport) printf '09-bugreport.zip' ;;
    esac
}

# Descripción legible de cada fuente.
describe_source() {
    case "$1" in
        procesos) printf 'Procesos en ejecución (ps -A)' ;;
        procesos-top) printf 'Procesos por CPU/memoria (top -n 1 -b)' ;;
        logcat-errores) printf 'Fallos y errores del log principal (*:E)' ;;
        logcat-crash) printf 'Buffer de crashes (logcat -b crash)' ;;
        logcat-sistema) printf 'Errores y avisos de system/main/events (*:W)' ;;
        kernel-dmesg) printf 'Registro del kernel en vivo (dmesg)' ;;
        kernel-anterior) printf 'Registro del kernel anterior (pstore; /proc/last_kmsg solo legacy)' ;;
        fallos-dropbox) printf 'Historial de fallos y ANR (dumpsys dropbox)' ;;
        bugreport) printf 'Informe completo del dispositivo (bugreport)' ;;
    esac
}

# Comando adb de cada fuente, impreso como una línea con argumentos citados.
command_for_source() {
    local -a base
    mapfile -t base < <(adb_args)
    local -a cmd
    case "$1" in
        procesos) cmd=("${base[@]}" shell ps -A) ;;
        procesos-top) cmd=("${base[@]}" shell top -n 1 -b) ;;
        logcat-errores) cmd=("${base[@]}" logcat -d -v threadtime '*:E') ;;
        logcat-crash) cmd=("${base[@]}" logcat -d -b crash -v threadtime) ;;
        logcat-sistema) cmd=("${base[@]}" logcat -d -b system -b main -b events -v threadtime '*:W') ;;
        kernel-dmesg) cmd=("${base[@]}" shell dmesg -T) ;;
        kernel-anterior)
            # La captura real hace tres pasos: lista pstore, vuelca su
            # contenido y, como fallback legacy, /proc/last_kmsg.
            local -a ls_cmd=("${base[@]}" shell ls -l /sys/fs/pstore)
            local -a cat_cmd=("${base[@]}" shell cat '/sys/fs/pstore/*')
            local -a last_cmd=("${base[@]}" shell cat /proc/last_kmsg)
            printf '( '
            printf '%q ' "${ls_cmd[@]}"; printf '; '
            printf '%q ' "${cat_cmd[@]}"; printf '; '
            printf '%q ' "${last_cmd[@]}"; printf ')'
            printf '\n'
            return 0
            ;;
        fallos-dropbox) cmd=("${base[@]}" shell dumpsys dropbox --print) ;;
        bugreport) cmd=("${base[@]}" bugreport) ;;
    esac
    printf '%q ' "${cmd[@]}"
    printf '\n'
}

# Ejecuta una fuente y registra su resultado en los arrays globales.
# Un fallo en una fuente (p. ej. dmesg sin root) no aborta el resto.
declare -a DONE_SOURCES=() DONE_FILES=() DONE_CODES=() DONE_DESCS=()
run_source() {
    local source="$1" file="$2"
    local -a base cmd
    mapfile -t base < <(adb_args)
    local code=0
    log "capturando $source -> $file"
    case "$source" in
        procesos) cmd=("${base[@]}" shell ps -A) ;;
        procesos-top) cmd=("${base[@]}" shell top -n 1 -b) ;;
        logcat-errores) cmd=("${base[@]}" logcat -d -v threadtime '*:E') ;;
        logcat-crash) cmd=("${base[@]}" logcat -d -b crash -v threadtime) ;;
        logcat-sistema) cmd=("${base[@]}" logcat -d -b system -b main -b events -v threadtime '*:W') ;;
        kernel-dmesg)
            cmd=("${base[@]}" shell dmesg -T)
            "${cmd[@]}" >"$file" 2>"$file.err" || code=$?
            if (( code != 0 )); then
                log "dmesg -T falló (código $code); reintentando con dmesg sin -T"
                cmd=("${base[@]}" shell dmesg)
                code=0
                "${cmd[@]}" >"$file" 2>"$file.err" || code=$?
            fi
            ;;
        kernel-anterior)
            {
                echo "== /sys/fs/pstore =="
                if ! "${base[@]}" shell ls -l /sys/fs/pstore; then
                    echo "pstore no disponible o sin permiso"
                fi
                echo "== contenido de pstore =="
                if ! "${base[@]}" shell cat '/sys/fs/pstore/*'; then
                    echo "sin archivos legibles en pstore"
                fi
                echo "== /proc/last_kmsg (legacy; vacío en kernels modernos) =="
                "${base[@]}" shell cat /proc/last_kmsg || echo "last_kmsg no disponible"
            } >"$file" 2>"$file.err" || code=$?
            ;;
        fallos-dropbox) cmd=("${base[@]}" shell dumpsys dropbox --print) ;;
        bugreport) cmd=("${base[@]}" bugreport) ;;
    esac
    if [[ "$source" != kernel-dmesg && "$source" != kernel-anterior ]]; then
        if "${cmd[@]}" >"$file" 2>"$file.err"; then code=0; else code=$?; fi
    fi
    if (( code != 0 )); then
        log "ADVERTENCIA: $source terminó con código $code; revisa $file.err"
    fi
    DONE_SOURCES+=("$source")
    DONE_FILES+=("$file")
    DONE_CODES+=("$code")
    DONE_DESCS+=("$(describe_source "$source")")
}

print_plan() {
    local source file
    printf 'PLAN DE TRAZAS ADB (dry-run, sin cambios)\n'
    printf 'Versión: %s | serial: %s | salida: %s\n' "$TRACES_VERSION" "${SERIAL:-<único dispositivo>}" "$OUT_DIR"
    IFS=',' read -r -a wanted <<< "$SOURCES"
    for source in "${wanted[@]}"; do
        file="$(file_for_source "$source")"
        printf '+ %s> %s\n' "$(command_for_source "$source")" "$file"
    done
    printf 'Manifiesto: MANIFIESTO.txt (comando, código, bytes y SHA-256 por fuente)\n'
}

print_plan_json() {
    local source file first=1
    printf '{\n'
    printf '  "version": "%s",\n' "$TRACES_VERSION"
    printf '  "serial": "%s",\n' "$SERIAL"
    printf '  "out_dir": "%s",\n' "$OUT_DIR"
    printf '  "dry_run": %s,\n' "$([[ $DRY_RUN -eq 1 ]] && echo true || echo false)"
    printf '  "sources": ['
    IFS=',' read -r -a wanted <<< "$SOURCES"
    for source in "${wanted[@]}"; do
        (( first )) && first=0 || printf ', '
        printf '"%s"' "$source"
    done
    printf '],\n  "files": [\n'
    first=1
    for source in "${wanted[@]}"; do
        file="$(file_for_source "$source")"
        (( first )) && first=0 || printf ',\n'
        printf '    {"source": "%s", "description": "%s", "file": "%s", "command": "%s"}' \
            "$source" "$(describe_source "$source")" "$file" "$(command_for_source "$source" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/ *$//')"
    done
    printf '\n  ]\n}\n'
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

capture() {
    check_device
    umask 077
    local stamp safe_serial run_dir
    stamp="$(date -u +%Y%m%d-%H%M%S)"
    safe_serial="${SERIAL:-sin-serial}"
    safe_serial="${safe_serial//:/_}"
    run_dir="$OUT_DIR/${stamp}_${safe_serial}"
    mkdir -p "$run_dir"
    chmod 0700 "$run_dir"
    log "evidencia en $run_dir (0700; material sensible)"

    local source file
    IFS=',' read -r -a wanted <<< "$SOURCES"
    for source in "${wanted[@]}"; do
        file="$run_dir/$(file_for_source "$source")"
        run_source "$source" "$file"
    done

    local manifest="$run_dir/MANIFIESTO.txt"
    {
        printf 'MANIFIESTO DE TRAZAS ADB\n'
        printf 'versión: %s\n' "$TRACES_VERSION"
        printf 'alcance: %s\n' "$(scope_status "$SCOPE_FILE")"
        printf 'fecha UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'serial: %s\n' "${SERIAL:-<único dispositivo>}"
        printf 'directorio: %s\n' "$run_dir"
        printf '\n%-18s %-6s %10s  %s\n' "fuente" "código" "bytes" "archivo (SHA-256)"
        local i bytes sha
        for i in "${!DONE_SOURCES[@]}"; do
            bytes="$(stat -c%s "${DONE_FILES[$i]}" 2>/dev/null || echo 0)"
            sha="$(sha256sum "${DONE_FILES[$i]}" 2>/dev/null | cut -d' ' -f1 || echo -)"
            printf '%-18s %-6s %10s  %s (%s)\n' "${DONE_SOURCES[$i]}" "${DONE_CODES[$i]}" "$bytes" \
                "$(basename "${DONE_FILES[$i]}")" "$sha"
            printf '  %s\n' "${DONE_DESCS[$i]}"
        done
        printf '\nRetención: material sensible; consérvalo solo según la autorización vigente.\n'
    } >"$manifest"
    chmod 0600 "$manifest"

    local warnings=0 code
    for code in "${DONE_CODES[@]}"; do (( code != 0 )) && warnings=$((warnings + 1)); done
    log "captura completa en $run_dir"
    if (( warnings )); then
        log "ADVERTENCIAS: $warnings fuente(s) fallaron; revisa los .err y el manifiesto"
        log "dmesg y pstore suelen fallar sin root; en kernels modernos /proc/last_kmsg sale vacío por diseño"
    fi
    printf 'Manifiesto: %s\n' "$manifest"
}

main() {
    while (($#)); do
        case "$1" in
            --serial) (($# >= 2)) || fail "--serial requiere SERIAL"; SERIAL="$2"; shift 2 ;;
            --out-dir) (($# >= 2)) || fail "--out-dir requiere PATH"; OUT_DIR="$2"; shift 2 ;;
            --sources) (($# >= 2)) || fail "--sources requiere LISTA"; SOURCES="$2"; shift 2 ;;
            --scope-file) (($# >= 2)) || fail "--scope-file requiere PATH"; SCOPE_FILE="$2"; shift 2 ;;
            --include-bugreport) INCLUDE_BUGREPORT=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            --plan-json) PLAN_JSON=1; shift ;;
            --confirm) CONFIRM=1; shift ;;
            -h|--help) usage; return 0 ;;
            *) fail "opción desconocida: $1" ;;
        esac
    done

    if [[ -z "$SOURCES" ]]; then
        SOURCES="$DEFAULT_SOURCES"
        (( INCLUDE_BUGREPORT )) && SOURCES="$SOURCES,bugreport"
    elif (( INCLUDE_BUGREPORT )) && [[ ",$SOURCES," != *",bugreport,"* ]]; then
        SOURCES="$SOURCES,bugreport"
    fi
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
    validate_sources

    if (( PLAN_JSON )); then print_plan_json; return 0; fi
    if (( DRY_RUN )); then print_plan; return 0; fi
    (( CONFIRM )) || fail "captura real sin --confirm; usa --dry-run para revisar el plan y --confirm para capturar (dispositivo autorizado)"
    capture
}

main "$@"
