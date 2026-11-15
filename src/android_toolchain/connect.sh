#!/usr/bin/env bash
#
# Conexión ADB — verificar el estado del dispositivo y forzar la
# conexión (USB y TCP). Solo sobre dispositivos de laboratorio
# autorizados, con confirmación explícita para cualquier acción que
# cambie el estado (reiniciar el servidor, reconectar o conectar por
# TCP). La verificación sola es de solo lectura y no necesita
# confirmación.
#
# La conexión por TCP exige una IP explícita del operador
# (--tcp IP[:PUERTO]); nunca se buscan dispositivos en la red.
# Un dispositivo `unauthorized` NO se puede forzar: la autorización
# RSA se acepta en la pantalla del dispositivo y no hay forma
# legítima de saltársela. El script lo detecta, lo marca como
# NO AUTORIZADO y explica cómo resolverlo.
#
# Cada ejecución guarda un reporte en un directorio de evidencia
# fuera del árbol del proyecto.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/android_toolchain/scope.sh
source "$SCRIPT_DIR/scope.sh"

CONNECT_VERSION="2.1.0"
OUT_DIR="${OUT_DIR:-$HOME/security-tools/connections}"
SERIAL=""
SCOPE_FILE=""
TCP_TARGET=""
FORCE=0
TIMEOUT=15
DRY_RUN=0
PLAN_JSON=0
CONFIRM=0

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 2
}

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

usage() {
    cat <<'EOF'
Uso: connect.sh [opciones]

  --serial SERIAL        Serial del dispositivo sobre el que actuar.
                         Sin serial se verifica todo lo visible en `adb devices`;
                         para forzar se exige un único dispositivo `device` o --serial.
  --tcp IP[:PUERTO]      Conectar por TCP a una IP explícita (puerto default 5555).
                         Nunca se buscan dispositivos en la red: la IP la da el operador.
  --force                Forzar la conexión: reinicia el servidor ADB, reconecta
                         los dispositivos fuera de línea y espera al dispositivo.
  --timeout SEGUNDOS     Espera máxima de `adb wait-for-device` (default: 15).
  --out-dir PATH         Directorio base de evidencia (default: $HOME/security-tools/connections).
  --scope-file PATH      Archivo de alcance de laboratorio (allowlist).
                         Default: $HOME/security-tools/scope si existe.
                         Cada ejecución crea <out-dir>/CONEXION-AAAAMMDD-HHMMSS_<serial|todos>/.
  --dry-run              Muestra el plan; no llama a adb ni crea directorios.
  --plan-json            Emite el plan como JSON y no ejecuta la conexión.
  --confirm              Confirmación explícita para forzar o conectar por TCP.
                         Sin --dry-run ni --confirm, esas acciones se rechazan.
  -h, --help             Muestra esta ayuda.

Ejemplos:
  ./src/android_toolchain/connect.sh --dry-run
  ./src/android_toolchain/connect.sh
  ./src/android_toolchain/connect.sh --serial emulator-5554 --force --confirm
  ./src/android_toolchain/connect.sh --tcp 192.168.1.42 --confirm
  ./src/android_toolchain/connect.sh --tcp 192.168.1.42:5555 --force --confirm --timeout 30
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

validate_tcp() {
    [[ -z "$TCP_TARGET" ]] && return 0
    local ip port
    ip="${TCP_TARGET%%:*}"
    port="${TCP_TARGET#*:}"
    [[ "$port" == "$TCP_TARGET" ]] && port="5555"
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "IP no válida para --tcp; usa IPv4, p. ej. 192.168.1.42 o 192.168.1.42:5555"
    local octet
    IFS='.' read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        (( octet >= 0 && octet <= 255 )) || fail "octeto fuera de rango en la IP: $ip"
    done
    [[ "$port" =~ ^[0-9]+$ ]] || fail "puerto no válido para --tcp: $port"
    (( port >= 1 && port <= 65535 )) || fail "puerto no válido para --tcp: $port"
    TCP_TARGET="$ip:$port"
}

validate_timeout() {
    [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || fail "el timeout debe ser un entero entre 1 y 300 segundos"
    (( TIMEOUT >= 1 && TIMEOUT <= 300 )) || fail "el timeout debe ser un entero entre 1 y 300 segundos"
}

# Pasos del plan, en orden, como líneas "comando" legibles.
plan_steps() {
    printf 'adb version\n'
    printf 'adb start-server\n'
    printf 'adb devices -l\n'
    if [[ -n "$SERIAL" ]]; then
        printf 'adb -s %s get-state\n' "$SERIAL"
        printf 'adb -s %s shell getprop ro.product.model\n' "$SERIAL"
    fi
    if (( FORCE )); then
        printf 'adb kill-server\n'
        printf 'adb start-server\n'
        printf 'adb reconnect\n'
        printf 'timeout %s adb wait-for-device\n' "$TIMEOUT"
        printf 'adb devices -l\n'
    fi
    if [[ -n "$TCP_TARGET" ]]; then
        printf 'adb connect %s\n' "$TCP_TARGET"
        printf 'adb devices -l\n'
    fi
}

print_plan() {
    printf 'PLAN DE CONEXIÓN ADB (dry-run, sin cambios)\n'
    printf 'Versión: %s | serial: %s | TCP: %s | forzar: %s | timeout: %s s | salida: %s\n' \
        "$CONNECT_VERSION" "${SERIAL:-<todos>}" "${TCP_TARGET:-<ninguno>}" \
        "$([[ $FORCE -eq 1 ]] && echo sí || echo no)" "$TIMEOUT" "$OUT_DIR"
    local step
    while IFS= read -r step; do
        printf '+ %s\n' "$step"
    done < <(plan_steps)
    printf 'Reporte: REPORTE.txt (estado por dispositivo y resultado de cada paso)\n'
    printf 'Manifiesto: MANIFIESTO.txt (comando, código, bytes y SHA-256)\n'
    if (( FORCE || ${#TCP_TARGET} > 0 )); then
        printf 'Acción real: exige --confirm (o confirmar el diálogo en la GUI).\n'
    else
        printf 'Solo verificación (solo lectura): no exige --confirm.\n'
    fi
}

print_plan_json() {
    printf '{\n'
    printf '  "version": "%s",\n' "$CONNECT_VERSION"
    printf '  "serial": "%s",\n' "$SERIAL"
    printf '  "tcp_target": "%s",\n' "$TCP_TARGET"
    printf '  "force": %s,\n' "$([[ $FORCE -eq 1 ]] && echo true || echo false)"
    printf '  "timeout": %s,\n' "$TIMEOUT"
    printf '  "out_dir": "%s",\n' "$OUT_DIR"
    printf '  "dry_run": %s,\n' "$([[ $DRY_RUN -eq 1 ]] && echo true || echo false)"
    printf '  "steps": ['
    local step first=1
    while IFS= read -r step; do
        (( first )) && first=0 || printf ', '
        printf '"%s"' "$(printf '%s' "$step" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    done < <(plan_steps)
    printf ']\n}\n'
}

# Estado de un serial según `adb devices` (device, unauthorized,
# offline, no device, ...). Vacío si no aparece.
device_state() {
    local serial="$1"
    adb devices | awk -v s="$serial" '$1 == s { print $2; exit }'
}

# Veredicto legible para un estado de adb.
verdict_for_state() {
    case "$1" in
        device) printf 'CONECTADO' ;;
        unauthorized) printf 'NO AUTORIZADO (acepta la huella RSA en el dispositivo)' ;;
        offline) printf 'FUERA DE LÍNEA (reconecta o vuelve a enchufar el USB)' ;;
        "no permissions") printf 'SIN PERMISOS (revisa udev/usuario; no es un fallo del dispositivo)' ;;
        "") printf 'SIN CONEXIÓN (no aparece en adb devices)' ;;
        *) printf 'ESTADO DESCONOCIDO: %s' "$1" ;;
    esac
}

# Ejecuta un paso, lo registra en el reporte y devuelve su código.
# Un paso que falla no aborta el resto.
declare -a DONE_STEPS=() DONE_CODES=()
run_step() {
    local desc="$1"
    shift
    local code=0
    log "$desc"
    {
        printf '\n== %s ==\n$ ' "$desc"
        printf '%q ' "$@"
        printf '\n'
    } >>"$REPORT"
    if "$@" >>"$REPORT" 2>&1; then code=0; else code=$?; fi
    if (( code != 0 )); then
        log "ADVERTENCIA: $desc terminó con código $code"
    fi
    DONE_STEPS+=("$desc")
    DONE_CODES+=("$code")
    return 0
}

connect() {
    command -v adb >/dev/null 2>&1 || fail "adb no está instalado; instala android-tools-adb"
    umask 077
    local stamp safe_serial run_dir
    stamp="$(date -u +%Y%m%d-%H%M%S)"
    safe_serial="${SERIAL:-todos}"
    safe_serial="${safe_serial//:/_}"
    run_dir="$OUT_DIR/CONEXION-${stamp}_${safe_serial}"
    mkdir -p "$run_dir"
    chmod 0700 "$run_dir"
    REPORT="$run_dir/REPORTE.txt"
    log "evidencia en $run_dir (0700)"

    {
        printf 'REPORTE DE CONEXIÓN ADB\n'
        printf 'versión: %s\n' "$CONNECT_VERSION"
        printf 'alcance: %s\n' "$(scope_status "$SCOPE_FILE")"
        printf 'fecha UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'serial: %s\n' "${SERIAL:-<todos>}"
        printf 'TCP: %s\n' "${TCP_TARGET:-<ninguno>}"
        printf 'forzar: %s | timeout: %s s\n' "$([[ $FORCE -eq 1 ]] && echo sí || echo no)" "$TIMEOUT"
    } >"$REPORT"
    chmod 0600 "$REPORT"

    run_step "versión del servidor ADB" adb version
    run_step "arranque del servidor ADB" adb start-server
    run_step "dispositivos visibles" adb devices -l

    local target_serial="$SERIAL"
    if [[ -z "$target_serial" ]]; then
        # Sin serial: si hay exactamente un dispositivo, se actúa sobre él.
        local count
        count="$(adb devices | awk '$2 == "device" { n++ } END { print n + 0 }')"
        if [[ "$count" -eq 1 ]]; then
            target_serial="$(adb devices | awk '$2 == "device" { print $1; exit }')"
            log "único dispositivo: $target_serial"
        fi
    fi

    if [[ -n "$target_serial" ]]; then
        local state
        state="$(device_state "$target_serial")"
        log "estado de $target_serial: ${state:-<no aparece>}"
        run_step "estado de $target_serial" adb -s "$target_serial" get-state
        run_step "modelo de $target_serial" adb -s "$target_serial" shell getprop ro.product.model
        printf '\nveredicto inicial %s: %s\n' "$target_serial" "$(verdict_for_state "$state")" >>"$REPORT"
    fi

    if (( FORCE )); then
        log "forzando conexión: reinicio del servidor y reconexión"
        run_step "parada del servidor ADB" adb kill-server
        run_step "arranque del servidor ADB" adb start-server
        run_step "reconexión de dispositivos" adb reconnect
        run_step "espera del dispositivo (${TIMEOUT}s)" timeout "$TIMEOUT" adb wait-for-device
        run_step "dispositivos visibles tras forzar" adb devices -l
    fi

    if [[ -n "$TCP_TARGET" ]]; then
        log "conectando por TCP a $TCP_TARGET"
        run_step "conexión TCP a $TCP_TARGET" adb connect "$TCP_TARGET"
        run_step "dispositivos visibles tras conectar" adb devices -l
    fi

    # Veredicto final por dispositivo visible.
    {
        printf '\n== VEREDICTO FINAL ==\n'
        local line serial state
        while IFS= read -r line; do
            [[ "$line" == *"List of devices"* || -z "$line" ]] && continue
            serial="${line%%[[:space:]]*}"
            state="$(device_state "$serial")"
            printf '%s: %s\n' "$serial" "$(verdict_for_state "$state")"
        done < <(adb devices)
        if [[ -n "$target_serial" ]]; then
            state="$(device_state "$target_serial")"
            printf '\nobjetivo %s: %s\n' "$target_serial" "$(verdict_for_state "$state")"
            if [[ "$state" == "unauthorized" ]]; then
                printf 'NO AUTORIZADO no se puede forzar: en el teléfono, acepta el diálogo\n'
                printf 'de depuración USB con la huella RSA de este equipo. Si el diálogo no\n'
                printf 'sale, revoca las autorizaciones (Opciones de desarrollador > Revocar\n'
                printf 'autorizaciones de depuración USB) y vuelve a enchufar el USB.\n'
            fi
            if [[ "$state" == "offline" ]]; then
                printf 'FUERA DE LÍNEA: prueba a desenchufar y enchufar el USB, cambiar de\n'
                printf 'puerto o cable, o adb reconnect de nuevo tras reiniciar el servidor.\n'
            fi
        fi
        printf '\nNota: adb devices sin dispositivos no significa que la depuración esté\n'
        printf 'apagada: revisa el cable, el puerto USB, la depuración USB en el teléfono\n'
        printf 'y que sea el único servidor ADB en ejecución.\n'
    } >>"$REPORT"

    local manifest="$run_dir/MANIFIESTO.txt"
    {
        printf 'MANIFIESTO DE CONEXIÓN ADB\n'
        printf 'versión: %s\n' "$CONNECT_VERSION"
        printf 'fecha UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'serial: %s\n' "${SERIAL:-<todos>}"
        printf 'TCP: %s\n' "${TCP_TARGET:-<ninguno>}"
        printf 'directorio: %s\n' "$run_dir"
        printf '\n%-46s %-6s %10s  %s\n' "paso" "código" "bytes" "archivo (SHA-256)"
        local bytes sha
        bytes="$(stat -c%s "$REPORT" 2>/dev/null || echo 0)"
        sha="$(sha256sum "$REPORT" 2>/dev/null | cut -d' ' -f1 || echo -)"
        printf '%-46s %-6s %10s  %s (%s)\n' "reporte" "-" "$bytes" "REPORTE.txt" "$sha"
        local i
        for i in "${!DONE_STEPS[@]}"; do
            printf '%-46s %-6s\n' "${DONE_STEPS[$i]}" "${DONE_CODES[$i]}"
        done
        printf '\nRetención: el reporte puede contener seriales y modelos; consérvalo según la autorización vigente.\n'
    } >"$manifest"
    chmod 0600 "$manifest"

    local failures=0 code
    for code in "${DONE_CODES[@]}"; do (( code != 0 )) && failures=$((failures + 1)); done
    log "conexión verificada; reporte en $REPORT"
    if (( failures )); then
        log "ADVERTENCIAS: $failures paso(s) fallaron; revisa el reporte"
    fi
    printf 'Reporte: %s\n' "$REPORT"
    printf 'Manifiesto: %s\n' "$manifest"
}

main() {
    while (($#)); do
        case "$1" in
            --serial) (($# >= 2)) || fail "--serial requiere SERIAL"; SERIAL="$2"; shift 2 ;;
            --tcp) (($# >= 2)) || fail "--tcp requiere IP[:PUERTO]"; TCP_TARGET="$2"; shift 2 ;;
            --force) FORCE=1; shift ;;
            --timeout) (($# >= 2)) || fail "--timeout requiere SEGUNDOS"; TIMEOUT="$2"; shift 2 ;;
            --out-dir) (($# >= 2)) || fail "--out-dir requiere PATH"; OUT_DIR="$2"; shift 2 ;;
            --scope-file) (($# >= 2)) || fail "--scope-file requiere PATH"; SCOPE_FILE="$2"; shift 2 ;;
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
    validate_tcp
    if [[ -n "$TCP_TARGET" ]]; then scope_check_tcp "$SCOPE_FILE" "${TCP_TARGET%%:*}"; fi
    validate_timeout
    validate_path "$OUT_DIR"
    if [[ "$OUT_DIR" != /* ]]; then OUT_DIR="$PWD/$OUT_DIR"; fi
    OUT_DIR="$(realpath -m -- "$OUT_DIR")"

    if (( PLAN_JSON )); then print_plan_json; return 0; fi
    if (( DRY_RUN )); then print_plan; return 0; fi
    if (( FORCE || ${#TCP_TARGET} > 0 )); then
        (( CONFIRM )) || fail "forzar o conectar por TCP sin --confirm; usa --dry-run para revisar el plan y --confirm para ejecutar (dispositivo autorizado)"
    fi
    connect
}

main "$@"
