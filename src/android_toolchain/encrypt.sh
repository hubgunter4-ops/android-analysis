#!/usr/bin/env bash
#
# ENCRYPT — verificar el cifrado del sistema Android y cifrar/descifrar
# archivos, desde Ubuntu, solo sobre dispositivos de laboratorio
# autorizados y dentro del alcance de laboratorio.
#
# LÍMITE HONESTO: esta herramienta NO activa el cifrado del sistema.
# Desde Android 10 el cifrado es por archivos (FBE) y viene activo de
# fábrica; lo controla el sistema, no una app ni ADB. Aquí solo se
# VERIFICA el estado (getprop ro.crypto.*) y se guía al usuario a
# Ajustes > Seguridad si el dispositivo no está cifrado.
#
# Cifrado de archivos (verificable, sin root, sin red):
# - Ubuntu: OpenSSL `enc -aes-256-cbc -pbkdf2 -salt`, clave derivada de
#   una contraseña leída de un archivo 0600 (`--password-file`). Salida
#   `.aes256` (formato salted de OpenSSL, cabecera "Salted__" + salt de
#   8 bytes). Este formato NO lo abre la app DeviceCrypt ni viceversa:
#   la app usa su propia clave en Android Keystore (ver docs).
# - App DeviceCrypt (android-app/): AES/GCM/NoPadding + AndroidKeyStore,
#   formato `.crypt` (magic "DCRYPT01" + IV 12 bytes + ciphertext+tag).
# La contraseña nunca se escribe en el log ni se pasa en argv: solo
# `-pass file:<archivo-0600>`; con `--delete-password-file` el script
# borra ese archivo tras usarlo (solo en ejecución real, nunca en
# dry-run ni plan-json).
#
# La evidencia queda fuera del árbol del proyecto, con manifiesto y
# SHA-256 por archivo. El dry-run nunca escribe ni cifra nada.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/android_toolchain/scope.sh
source "$SCRIPT_DIR/scope.sh"

ENCRYPT_VERSION="2.2.0"
OUT_DIR="${OUT_DIR:-$HOME/security-tools/encrypt}"
SERIAL=""
SCOPE_FILE=""
MODE="verify"
FILE=""
OUT=""
PASSWORD_FILE=""
DELETE_PASSWORD_FILE=0
APK=""
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
Uso: encrypt.sh [opciones]

  --serial SERIAL        Serial del dispositivo (verificado en `adb devices`).
                         Sin serial se exige exactamente un dispositivo `device`
                         (solo en los modos verify e install-app).
  --out-dir PATH         Directorio base de evidencia (default: $HOME/security-tools/encrypt).
                         Cada operación crea <out-dir>/AAAAMMDD-HHMMSS_<serial|local>/.
  --mode MODO            verify | encrypt-file | decrypt-file | install-app
                         (default: verify).
  --file RUTA            Archivo de entrada (encrypt-file / decrypt-file).
  --out RUTA             Archivo de salida (default: <entrada>.aes256 al cifrar;
                         al descifrar quita .aes256 o añade .dec).
  --password-file RUTA   Archivo 0600 con la contraseña (encrypt-file /
                         decrypt-file). Obligatorio en ejecución real.
  --delete-password-file Borra el archivo de contraseña tras usarlo
                         (solo en ejecución real, nunca en dry-run).
  --apk RUTA             APK de DeviceCrypt a instalar (default: el APK debug
                         de android-app/ en este repo, si existe).
  --scope-file PATH      Archivo de alcance de laboratorio (allowlist).
                         Default: $HOME/security-tools/scope si existe.
  --dry-run              Muestra el plan; no llama a adb ni a openssl,
                         no escribe ni cifra nada.
  --plan-json            Emite el plan como JSON y no ejecuta nada.
  --confirm              Confirmación explícita para una operación real.
                         Sin --dry-run ni --confirm la operación se rechaza.
  -h, --help             Muestra esta ayuda.

Algoritmo Ubuntu (encrypt-file / decrypt-file):
  openssl enc -aes-256-cbc -pbkdf2 -salt -pass file:<archivo-0600>
  Salida .aes256 con cabecera "Salted__" + salt de 8 bytes. La app
  DeviceCrypt usa otro formato (.crypt, AES/GCM + Keystore) y NO abre
  archivos .aes256: son dos rutas distintas, documentadas en
  docs/encrypt-android.md.

Ejemplos:
  ./src/android_toolchain/encrypt.sh --dry-run
  ./src/android_toolchain/encrypt.sh --dry-run --serial emulator-5554
  ./src/android_toolchain/encrypt.sh --serial emulator-5554 --confirm
  ./src/android_toolchain/encrypt.sh --mode encrypt-file --file ~/nota.txt \
      --password-file ~/.config/devicecrypt.pw --confirm
  ./src/android_toolchain/encrypt.sh --mode install-app --serial emulator-5554 --confirm
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

validate_mode() {
    case "$MODE" in
        verify|encrypt-file|decrypt-file|install-app) ;;
        *) fail "modo desconocido: $MODE (usa verify, encrypt-file, decrypt-file o install-app)" ;;
    esac
}

validate_password_file() {
    [[ -n "$PASSWORD_FILE" ]] || fail "encrypt-file y decrypt-file exigen --password-file (archivo 0600 con la contraseña)"
    [[ -f "$PASSWORD_FILE" ]] || fail "archivo de contraseña no encontrado: $PASSWORD_FILE"
    local perms
    perms="$(stat -c %a "$PASSWORD_FILE" 2>/dev/null || echo ?)"
    case "$perms" in
        400|600) ;;
        *) fail "el archivo de contraseña debe tener permisos 400 o 600 (tiene $perms); la contraseña no debe ser legible por otros usuarios" ;;
    esac
}

# argv base de adb, sin shell: serial opcional.
adb_args() {
    if [[ -n "$SERIAL" ]]; then printf '%s\n' "adb" "-s" "$SERIAL"; else printf '%s\n' "adb"; fi
}

default_apk() {
    local root
    root="$(cd "$SCRIPT_DIR/../.." && pwd)"
    printf '%s/android-app/app-debug.apk\n' "$root"
}

default_out() {
    if [[ "$MODE" == encrypt-file ]]; then
        printf '%s.aes256\n' "$FILE"
    else
        case "$FILE" in
            *.aes256) printf '%s\n' "${FILE%.aes256}" ;;
            *) printf '%s.dec\n' "$FILE" ;;
        esac
    fi
}

openssl_cmd() {
    local -a cmd=(openssl enc -aes-256-cbc -pbkdf2 -salt)
    [[ "$MODE" == decrypt-file ]] && cmd+=(-d)
    cmd+=(-in "$FILE" -out "$OUT" -pass "file:$PASSWORD_FILE")
    printf '%q ' "${cmd[@]}"
    printf '\n'
}

print_plan() {
    printf 'PLAN DE ENCRYPT (dry-run, sin cambios)\n'
    printf 'Versión: %s | modo: %s | serial: %s | salida: %s\n' \
        "$ENCRYPT_VERSION" "$MODE" "${SERIAL:-<único dispositivo|local>}" "$OUT_DIR"
    case "$MODE" in
        verify)
            local -a base
            mapfile -t base < <(adb_args)
            local prop
            for prop in ro.crypto.state ro.crypto.type ro.crypto.fde_algorithm ro.crypto.metadata.enabled; do
                printf '+ '
                printf '%q ' "${base[@]}" shell getprop "$prop"
                printf '\n'
            done
            printf 'Veredicto: CIFRADO / SIN CIFRAR / DESCONOCIDO según ro.crypto.state\n'
            printf 'Esta herramienta NO activa el cifrado del sistema (FBE, de fábrica desde Android 10).\n'
            ;;
        encrypt-file|decrypt-file)
            printf '+ %s\n' "$(openssl_cmd)"
            printf 'Algoritmo: AES-256-CBC + PBKDF2 + salt (OpenSSL); entrada: %s; salida: %s\n' "$FILE" "$OUT"
            printf 'Formato .aes256: NO intercambiable con el .crypt de DeviceCrypt (AES/GCM + Keystore).\n'
            ;;
        install-app)
            local -a base
            mapfile -t base < <(adb_args)
            printf '+ '
            printf '%q ' "${base[@]}" install -r "$APK"
            printf '\n'
            printf 'Instala DeviceCrypt (com.zapia.devicecrypt) en el dispositivo autorizado.\n'
            ;;
    esac
    printf 'Manifiesto: RESUMEN.txt + MANIFIESTO.txt (comando, código, bytes y SHA-256)\n'
}

print_plan_json() {
    local steps
    case "$MODE" in
        verify)
            steps='"adb shell getprop ro.crypto.state", "adb shell getprop ro.crypto.type", "adb shell getprop ro.crypto.fde_algorithm", "adb shell getprop ro.crypto.metadata.enabled"'
            ;;
        encrypt-file|decrypt-file)
            steps="\"openssl enc -aes-256-cbc -pbkdf2 -salt\""
            ;;
        install-app)
            steps='"adb install -r <apk>"'
            ;;
    esac
    printf '{\n'
    printf '  "version": "%s",\n' "$ENCRYPT_VERSION"
    printf '  "mode": "%s",\n' "$MODE"
    printf '  "serial": "%s",\n' "$SERIAL"
    printf '  "out_dir": "%s",\n' "$OUT_DIR"
    printf '  "file": "%s",\n' "$FILE"
    printf '  "out": "%s",\n' "$OUT"
    printf '  "apk": "%s",\n' "$APK"
    printf '  "dry_run": %s,\n' "$([[ $DRY_RUN -eq 1 ]] && echo true || echo false)"
    printf '  "steps": [%s]\n}\n' "$steps"
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

make_run_dir() {
    umask 077
    local stamp safe_serial run_dir
    stamp="$(date -u +%Y%m%d-%H%M%S)"
    safe_serial="${SERIAL:-local}"
    safe_serial="${safe_serial//:/_}"
    run_dir="$OUT_DIR/${stamp}_${safe_serial}"
    mkdir -p "$run_dir"
    chmod 0700 "$run_dir"
    printf '%s\n' "$run_dir"
}

write_manifest() {
    local run_dir="$1" resumen="$2"
    local manifest="$run_dir/MANIFIESTO.txt"
    {
        printf 'MANIFIESTO DE ENCRYPT\n'
        printf 'versión: %s\n' "$ENCRYPT_VERSION"
        printf 'modo: %s\n' "$MODE"
        printf 'alcance: %s\n' "$(scope_status "$SCOPE_FILE")"
        printf 'fecha UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'serial: %s\n' "${SERIAL:-local}"
        printf 'directorio: %s\n' "$run_dir"
        printf '\n%s\n' "$resumen"
    } >"$manifest"
    chmod 0600 "$manifest"
    printf 'Manifiesto: %s\n' "$manifest"
}

run_verify() {
    check_device
    local -a base
    mapfile -t base < <(adb_args)
    local run_dir
    run_dir="$(make_run_dir)"
    log "evidencia en $run_dir (0700)"
    local out="$run_dir/01-cifrado-sistema.txt"
    local state="" type="" fde="" metadata=""
    state="$("${base[@]}" shell getprop ro.crypto.state 2>"$out.err" | tr -d '\r' || true)"
    type="$("${base[@]}" shell getprop ro.crypto.type 2>/dev/null | tr -d '\r' || true)"
    fde="$("${base[@]}" shell getprop ro.crypto.fde_algorithm 2>/dev/null | tr -d '\r' || true)"
    metadata="$("${base[@]}" shell getprop ro.crypto.metadata.enabled 2>/dev/null | tr -d '\r' || true)"
    local verdict="DESCONOCIDO"
    case "$state" in
        encrypted) verdict="CIFRADO" ;;
        unencrypted) verdict="SIN CIFRAR" ;;
    esac
    {
        printf 'VERIFICACIÓN DEL CIFRADO DEL SISTEMA\n'
        printf 'ro.crypto.state=%s\n' "$state"
        printf 'ro.crypto.type=%s\n' "$type"
        printf 'ro.crypto.fde_algorithm=%s\n' "$fde"
        printf 'ro.crypto.metadata.enabled=%s\n' "$metadata"
        printf 'veredicto: %s\n' "$verdict"
        printf '\nEsta herramienta NO activa el cifrado del sistema.\n'
        printf 'Desde Android 10 el cifrado es por archivos (FBE) y viene\n'
        printf 'activo de fábrica; lo controla el sistema.\n'
        if [[ "$verdict" == "SIN CIFRAR" ]]; then
            printf '\nSi el dispositivo no está cifrado, ve a Ajustes > Seguridad\n'
            printf '> Cifrado y credenciales y sigue el asistente del sistema\n'
            printf '(exige batería y bloqueo de pantalla; puede borrar datos\n'
            printf 'en dispositivos antiguos sin FBE).\n'
        fi
    } >"$out"
    chmod 0600 "$out"
    local resumen
    resumen="$(printf 'veredicto: %s (ro.crypto.state=%s, ro.crypto.type=%s)\narchivo: 01-cifrado-sistema.txt (%s)' \
        "$verdict" "$state" "$type" "$(sha256sum "$out" | cut -d' ' -f1)")"
    {
        printf 'RESUMEN DE ENCRYPT (verify)\n'
        printf 'veredicto: %s\n' "$verdict"
        printf 'ro.crypto.state=%s\n' "$state"
        printf 'ro.crypto.type=%s\n' "$type"
    } >"$run_dir/RESUMEN.txt"
    chmod 0600 "$run_dir/RESUMEN.txt"
    write_manifest "$run_dir" "$resumen"
    log "veredicto: $verdict"
}

run_file_crypto() {
    validate_password_file
    command -v openssl >/dev/null 2>&1 || fail "openssl no está instalado"
    [[ -f "$FILE" ]] || fail "archivo de entrada no encontrado: $FILE"
    local run_dir
    run_dir="$(make_run_dir)"
    log "evidencia en $run_dir (0700)"
    local in_sha in_bytes
    in_sha="$(sha256sum "$FILE" | cut -d' ' -f1)"
    in_bytes="$(stat -c%s "$FILE")"
    local code=0
    if [[ "$MODE" == encrypt-file ]]; then
        openssl enc -aes-256-cbc -pbkdf2 -salt -in "$FILE" -out "$OUT" -pass "file:$PASSWORD_FILE" || code=$?
    else
        openssl enc -d -aes-256-cbc -pbkdf2 -salt -in "$FILE" -out "$OUT" -pass "file:$PASSWORD_FILE" || code=$?
    fi
    if (( DELETE_PASSWORD_FILE )); then
        rm -f -- "$PASSWORD_FILE"
        log "archivo de contraseña borrado tras su uso"
    fi
    (( code == 0 )) || fail "openssl terminó con código $code (¿contraseña incorrecta al descifrar o archivo no válido?)"
    chmod 0600 "$OUT" 2>/dev/null || true
    local out_sha out_bytes
    out_sha="$(sha256sum "$OUT" | cut -d' ' -f1)"
    out_bytes="$(stat -c%s "$OUT")"
    local resumen
    resumen="$(printf 'algoritmo: openssl enc -aes-256-cbc -pbkdf2 -salt\nentrada: %s (%s bytes, SHA-256 %s)\nsalida: %s (%s bytes, SHA-256 %s)' \
        "$FILE" "$in_bytes" "$in_sha" "$OUT" "$out_bytes" "$out_sha")"
    {
        printf 'RESUMEN DE ENCRYPT (%s)\n' "$MODE"
        printf 'algoritmo: openssl enc -aes-256-cbc -pbkdf2 -salt\n'
        printf 'entrada: %s (%s bytes, SHA-256 %s)\n' "$FILE" "$in_bytes" "$in_sha"
        printf 'salida: %s (%s bytes, SHA-256 %s)\n' "$OUT" "$out_bytes" "$out_sha"
        printf 'formato .aes256: NO intercambiable con el .crypt de DeviceCrypt.\n'
    } >"$run_dir/RESUMEN.txt"
    chmod 0600 "$run_dir/RESUMEN.txt"
    write_manifest "$run_dir" "$resumen"
    log "operación completa: $FILE -> $OUT"
}

run_install_app() {
    check_device
    [[ -n "$APK" ]] || APK="$(default_apk)"
    [[ -f "$APK" ]] || fail "APK de DeviceCrypt no encontrada: $APK (compílala con ./android-app/gradlew -p android-app assembleDebug o descarga el artefacto de CI)"
    local -a base
    mapfile -t base < <(adb_args)
    local run_dir
    run_dir="$(make_run_dir)"
    log "evidencia en $run_dir (0700)"
    local apk_sha apk_bytes
    apk_sha="$(sha256sum "$APK" | cut -d' ' -f1)"
    apk_bytes="$(stat -c%s "$APK")"
    local out="$run_dir/01-instalar-app.txt"
    local code=0
    "${base[@]}" install -r "$APK" >"$out" 2>"$out.err" || code=$?
    chmod 0600 "$out"
    (( code == 0 )) || fail "adb install terminó con código $code; revisa $out y $out.err"
    grep -q 'Success' "$out" || fail "adb install no devolvió Success; revisa $out"
    local resumen
    resumen="$(printf 'apk: %s (%s bytes, SHA-256 %s)\nresultado: Success (ver 01-instalar-app.txt)' \
        "$APK" "$apk_bytes" "$apk_sha")"
    {
        printf 'RESUMEN DE ENCRYPT (install-app)\n'
        printf 'apk: %s (%s bytes, SHA-256 %s)\n' "$APK" "$apk_bytes" "$apk_sha"
        printf 'paquete: com.zapia.devicecrypt (DeviceCrypt 1.0)\n'
        printf 'resultado: Success\n'
    } >"$run_dir/RESUMEN.txt"
    chmod 0600 "$run_dir/RESUMEN.txt"
    write_manifest "$run_dir" "$resumen"
    log "DeviceCrypt instalada en el dispositivo"
}

main() {
    while (($#)); do
        case "$1" in
            --serial) (($# >= 2)) || fail "--serial requiere SERIAL"; SERIAL="$2"; shift 2 ;;
            --out-dir) (($# >= 2)) || fail "--out-dir requiere PATH"; OUT_DIR="$2"; shift 2 ;;
            --mode) (($# >= 2)) || fail "--mode requiere MODO"; MODE="$2"; shift 2 ;;
            --file) (($# >= 2)) || fail "--file requiere RUTA"; FILE="$2"; shift 2 ;;
            --out) (($# >= 2)) || fail "--out requiere RUTA"; OUT="$2"; shift 2 ;;
            --password-file) (($# >= 2)) || fail "--password-file requiere RUTA"; PASSWORD_FILE="$2"; shift 2 ;;
            --delete-password-file) DELETE_PASSWORD_FILE=1; shift ;;
            --apk) (($# >= 2)) || fail "--apk requiere RUTA"; APK="$2"; shift 2 ;;
            --scope-file) (($# >= 2)) || fail "--scope-file requiere PATH"; SCOPE_FILE="$2"; shift 2 ;;
            --dry-run) DRY_RUN=1; shift ;;
            --plan-json) PLAN_JSON=1; shift ;;
            --confirm) CONFIRM=1; shift ;;
            -h|--help) usage; return 0 ;;
            *) fail "opción desconocida: $1" ;;
        esac
    done

    validate_mode
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
    if [[ "$MODE" == encrypt-file || "$MODE" == decrypt-file ]]; then
        [[ -n "$FILE" ]] || fail "$MODE exige --file"
        validate_path "$FILE"
        [[ -z "$OUT" ]] && OUT="$(default_out)"
        validate_path "$OUT"
        if [[ -n "$PASSWORD_FILE" ]]; then validate_path "$PASSWORD_FILE"; fi
    fi
    if [[ "$MODE" == install-app && -n "$APK" ]]; then validate_path "$APK"; fi

    if (( PLAN_JSON )); then print_plan_json; return 0; fi
    if (( DRY_RUN )); then print_plan; return 0; fi
    (( CONFIRM )) || fail "operación real sin --confirm; usa --dry-run para revisar el plan y --confirm para ejecutar (dispositivo autorizado)"
    case "$MODE" in
        verify) run_verify ;;
        encrypt-file|decrypt-file) run_file_crypto ;;
        install-app) run_install_app ;;
    esac
}

main "$@"
