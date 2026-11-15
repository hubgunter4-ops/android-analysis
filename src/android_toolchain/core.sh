#!/usr/bin/env bash
#
# Android analysis toolchain installer — core
# Provisionamiento autorizado para reversing, instrumentación y análisis dinámico.

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="2.1.0"
TOOLS_DIR="${TOOLS_DIR:-$HOME/security-tools}"
JADX_VERSION="1.5.6"
JADX_URL="https://github.com/skylot/jadx/releases/download/v${JADX_VERSION}/jadx-${JADX_VERSION}.zip"
JADX_SHA256_EXPECTED="545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974"
DEX2JAR_COMMIT="b5bda4fb4935ae8b3869b422454ae3b3896c7bc1"
MOBSF_COMMIT="7a4785fb3b55949231dd2b5d7df82ccba02a114f"
DRY_RUN=0
INTERACTIVE=0
GUIDED=0
STATIC_ONLY=0
DYNAMIC_ONLY=0
SKIP_APT=0
PLAN_JSON=0
TRACES_ONLY=0
TRACES_SERIAL=""
TRACES_DIR=""
TRACES_SOURCES=""
TRACES_CONFIRM=0
AUDIT_ONLY=0
AUDIT_SERIAL=""
AUDIT_DIR=""
AUDIT_CHECKS=""
AUDIT_EXPECTED_KEY=""
AUDIT_SEED=""
AUDIT_NO_NETWORK_PROBE=0
AUDIT_CONFIRM=0
CONNECT_ONLY=0
CONNECT_SERIAL=""
CONNECT_DIR=""
CONNECT_TCP=""
CONNECT_FORCE=0
CONNECT_TIMEOUT=""
CONNECT_CONFIRM=0
ANALYZE_ONLY=0
ANALYZE_DIR=""
ANALYZE_FILES=()
ANALYZE_OUT_DIR=""
ANALYZE_PEDIR_BUGREPORT=0
ANALYZE_SERIAL=""
ANALYZE_CONFIRM=0
ANALYZE_MAX_MUESTRAS=""
ANALYZE_TIMEOUT=""
APPS_ONLY=0
APPS_SERIAL=""
APPS_DIR=""
APPS_TODAS=0
APPS_CONFIRM=0
SCOPE_FILE=""
BANNER_STYLE="${BANNER_STYLE:-$((RANDOM % 3))}"

banner() {
    local style="$BANNER_STYLE"
    [[ "$style" =~ ^[0-2]$ ]] || style=0
    if [[ -t 1 ]]; then printf '\033[38;5;141m'; fi
    case "$style" in
        0)
            cat <<'EOF'
+--------------------------------------------------------------------------+
| ANDROID TOOLCHAIN :: RE · STATIC · DYNAMIC · TRAFFIC                    |
| Authorized mobile assessment provisioning                               |
+--------------------------------------------------------------------------+
EOF
            ;;
        1)
            cat <<'EOF'
╭──────────────────────────────────────────────────────────────────────────╮
│  ANDROID ANALYSIS  ·  APK reversing  ·  Frida  ·  MobSF  ·  ADB          │
│  reproducible provisioning for authorized engagements                    │
╰──────────────────────────────────────────────────────────────────────────╯
EOF
            ;;
        2)
            cat <<'EOF'
[ APK ]  decompile / inspect / score
[ LIVE]  ADB / Frida / objection / proxy
[ SCOPE] authorized Android assessment only
EOF
            ;;
    esac
    if [[ -t 1 ]]; then printf '\033[0m'; fi
    printf '\nVersion %s | banner=%s | tools=%s\n\n' "$VERSION" "$style" "$TOOLS_DIR"
}

usage() {
    cat <<'EOF'
Uso: no4nn.sh [opciones]

  --tools-dir PATH       Directorio de instalación (default: $HOME/security-tools).
  --dry-run              Muestra el plan; no cambia el host ni descarga repositorios.
  --plan-json             Emite el plan como JSON y no ejecuta fases.
  --static-only          Ejecuta solo reversing/análisis estático.
  --dynamic-only         Ejecuta solo ADB, instrumentación y tráfico.
  --skip-apt             No ejecuta apt; útil en imágenes ya provisionadas.
  --banner-style 0|1|2   Selecciona la variante del banner.
  --interactive          Selector guiado de fase y modo.
  --guided               Explica el flujo y termina sin cambios.
  --gui                  Abre la interfaz Tkinter (equivale a ./install.sh --gui).
  -h, --help             Muestra esta ayuda.

Trazas ADB (no instala nada; captura procesos, fallos y kernel):
  --traces               Solo trazas; no ejecuta las fases de instalación.
  --traces-serial SERIAL Serial del dispositivo (verificado en `adb devices`; alias: --serial).
  --traces-dir PATH      Directorio base de evidencia (default: $HOME/security-tools/traces).
  --traces-sources LISTA Fuentes separadas por coma (ver traces.sh --help).
  --traces-confirm       Confirmación explícita para una captura real.
                         Sin --dry-run ni --traces-confirm la captura se rechaza.

Auditoría ADB (no instala nada; claves RSA, depuración, red y puerto 5555):
  --audit                Solo auditoría; no ejecuta las fases de instalación.
  --audit-serial SERIAL  Serial del dispositivo (verificado en `adb devices`; alias: --serial).
  --audit-dir PATH       Directorio base de evidencia (default: $HOME/security-tools/audits).
  --audit-checks LISTA   Comprobaciones separadas por coma (ver audit.sh --help).
  --audit-expected-key PATH Clave pública del operador para contrastar las autorizadas.
  --audit-seed N         Semilla de la aleatorización (orden, pausas, timeout de sonda).
  --audit-sin-sonda-red  Omite la sonda TCP desde la red al puerto 5555.
  --audit-confirm        Confirmación explícita para una auditoría real.
                         Sin --dry-run ni --audit-confirm la auditoría se rechaza.

  --connect              Solo conexión; no ejecuta las fases de instalación.
  --connect-serial SERIAL Serial del dispositivo (alias: --serial).
  --connect-dir PATH     Directorio base de evidencia (default: $HOME/security-tools/connections).
  --connect-tcp IP[:PUERTO] Conectar por TCP a una IP explícita (puerto default 5555).
  --connect-force        Forzar la conexión: reinicia el servidor, reconecta y espera.
  --connect-timeout N    Espera máxima de `adb wait-for-device` en segundos (default: 15).
  --scope-file PATH      Archivo de alcance de laboratorio (allowlist) para
                         trazas, auditoría y conexión (default: $HOME/security-tools/scope si existe).
  --connect-confirm      Confirmación explícita para forzar o conectar por TCP.
                         Sin --dry-run ni --connect-confirm esas acciones se rechazan.
                         La verificación sola no exige confirmación.

  --analyze              Solo análisis de trazas; no ejecuta las fases de instalación.
  --analyze-dir DIR      Carpeta de captura con .txt y/o .zip.
  --analyze-file ARCHIVO Archivo .txt o .zip subido (repetible).
  --analyze-out-dir PATH Directorio base de evidencia (default: $HOME/security-tools/analyses).
  --analyze-pedir-bugreport
                         Pide un bugreport al dispositivo con `adb bugreport` y lo analiza.
  --analyze-serial SERIAL Serial del dispositivo para pedir el bugreport (alias: --serial).
  --analyze-timeout N    Espera máxima del bugreport en segundos (default: 300).
  --analyze-max-muestras N Muestras por clase y archivo (default: 5).
  --analyze-confirm      Confirmación explícita para pedir un bugreport.
                         Sin --dry-run ni --analyze-confirm la petición se rechaza.
                         Analizar archivos ya subidos no exige confirmación.

  --apps                 Solo listado de apps; no ejecuta las fases de instalación.
  --apps-serial SERIAL   Serial del dispositivo (alias: --serial).
  --apps-dir PATH        Directorio base de evidencia (default: $HOME/security-tools/apps).
  --apps-todas           Incluir también las apps del sistema (default: solo terceros).
  --apps-confirm         Confirmación explícita para una recogida real.
                         Sin --dry-run ni --apps-confirm la recogida se rechaza.

Variables:
  JADX_SHA256             Compatibilidad: solo se acepta el SHA-256 fijado de JADX ${JADX_VERSION}.
  TOOLS_DIR               Igual que --tools-dir.

Ejemplos:
  ./src/no4nn.sh --dry-run --static-only
  ./src/no4nn.sh --plan-json --dynamic-only --tools-dir /opt/security-tools
  sudo -E ./src/no4nn.sh --tools-dir "$HOME/security-tools" --banner-style 1
  ./src/no4nn.sh --traces --dry-run --serial emulator-5554
  ./src/no4nn.sh --traces --serial emulator-5554 --traces-confirm
EOF
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 2
}

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

run() {
    if (( DRY_RUN )); then
        printf '+ '
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

sudo_run() {
    if (( DRY_RUN )); then
        run sudo "$@"
    elif (( EUID == 0 )); then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        fail "se necesita sudo para: $*"
    fi
}

validate_path() {
    local path="$1"
    [[ "$path" =~ ^[A-Za-z0-9_./:@+,-]+$ ]] || fail "ruta no válida; usa solo caracteres de ruta seguros"
    local part
    IFS='/' read -r -a path_parts <<< "$path"
    for part in "${path_parts[@]}"; do
        [[ "$part" != .. ]] || fail "ruta con traversal no permitida"
    done
    [[ "$path" != / ]] || fail "no se permite usar la raíz como directorio de herramientas"
}

validate_style() { [[ "$BANNER_STYLE" =~ ^[0-2]$ ]] || fail "banner debe ser 0, 1 o 2"; }

guided_flow() {
    cat <<'EOF'
Flujo ANDROID ANALYSIS: scope -> base/ADB -> APK tools -> static -> dynamic/Frida -> traffic -> summary.
[1] static-only: reversing y análisis estático; [2] dynamic-only: ADB/instrumentación; [3] all: cadena completa.
Trazas: --traces --dry-run revisa el plan (procesos, logcat, dmesg, pstore, dropbox) y --traces-confirm captura a archivos.
El modo guiado no instala nada. El modo interactivo pregunta si debe permanecer en dry-run antes de ejecutar.
EOF
}

interactive_select() {
    [[ -t 0 ]] || fail "--interactive requiere una terminal interactiva"
    guided_flow
    read -r -p "Selecciona [1] static [2] dynamic [3] all [q] cancelar: " choice
    case "$choice" in
        1) STATIC_ONLY=1; DYNAMIC_ONLY=0 ;;
        2) STATIC_ONLY=0; DYNAMIC_ONLY=1 ;;
        3) STATIC_ONLY=0; DYNAMIC_ONLY=0 ;;
        *) fail "operación cancelada por el operador" ;;
    esac
    read -r -p "¿Ejecutar instalación real? [s/N]: " execute
    case "${execute,,}" in
        s|si|sí|y|yes) DRY_RUN=0 ;;
        *) DRY_RUN=1 ;;
    esac
}

flow_transition() {
    log "[FLOW] scope -> validate -> $1 -> execute -> summary"
}

validate_checksum() {
    [[ -z "${JADX_SHA256:-}" || "$JADX_SHA256" == "$JADX_SHA256_EXPECTED" ]] || fail "JADX_SHA256 no coincide con el checksum fijado de JADX ${JADX_VERSION}"
}

plan_json() {
    local static_enabled=true dynamic_enabled=true
    if (( STATIC_ONLY )); then dynamic_enabled=false; fi
    if (( DYNAMIC_ONLY )); then static_enabled=false; fi
    printf '{\n'
    printf '  "version": "%s",\n' "$VERSION"
    printf '  "tools_dir": "%s",\n' "$TOOLS_DIR"
    printf '  "dry_run": %s,\n' "$([[ $DRY_RUN -eq 1 ]] && echo true || echo false)"
    printf '  "skip_apt": %s,\n' "$([[ $SKIP_APT -eq 1 ]] && echo true || echo false)"
    printf '  "static_enabled": %s,\n' "$static_enabled"
    printf '  "dynamic_enabled": %s,\n' "$dynamic_enabled"
    printf '  "phases": [\n'
    if [[ "$static_enabled" == true ]]; then
        printf '    "base", "adb", "apk-tools", "static-analysis"'
    elif [[ "$dynamic_enabled" == true ]]; then
        printf '    "base", "adb"'
    fi
    if [[ "$dynamic_enabled" == true ]]; then
        printf ',\n'
        printf '    "dynamic-instrumentation", "traffic-capture"\n'
    else
        printf '\n'
    fi
    printf '  ]\n}\n'
}

install_base() {
    log "[1/6] Dependencias base"
    (( SKIP_APT )) && { log "apt omitido por --skip-apt"; return; }
    sudo_run apt-get update
    sudo_run apt-get install -y build-essential git curl wget unzip python3 python3-pip python3-tk default-jdk
}

install_adb() {
    log "[2/6] Conexión y control del dispositivo (ADB)"
    if (( ! SKIP_APT )); then sudo_run apt-get install -y android-tools-adb android-tools-fastboot; fi
    if (( ! DRY_RUN )) && command -v adb >/dev/null 2>&1; then
        log "Dispositivos visibles; no se conecta ni modifica ninguno automáticamente"
        adb devices || true
    fi
    log "Requiere Depuración USB activada solo en el dispositivo de laboratorio"
}

install_apk_tools() {
    log "[3/6] Descompilación / desempaquetado de APK"
    if (( ! SKIP_APT )); then sudo_run apt-get install -y apktool; fi
    local jadx_dir="$TOOLS_DIR/jadx"
    local jadx_marker="$jadx_dir/.jadx.sha256"
    if [[ -d "$jadx_dir/bin" ]]; then
        [[ -f "$jadx_marker" && "$(<"$jadx_marker")" == "$JADX_SHA256_EXPECTED" ]] || fail "JADX existente sin marcador de integridad válido; reinstala: $jadx_dir"
        log "jadx ya existe: $jadx_dir"
    elif (( DRY_RUN )); then
        log "Descarga planificada: JADX ${JADX_VERSION} por HTTPS con SHA-256 fijado"
    else
        local url archive
        url="$JADX_URL"
        archive="$(mktemp --tmpdir jadx.XXXXXX.zip)"
        trap 'rm -f "${archive:-}"' RETURN
        curl -fL --proto '=https' --tlsv1.2 -o "$archive" "$url"
        echo "${JADX_SHA256_EXPECTED}  ${archive}" | sha256sum -c -
        mkdir -p "$jadx_dir"
        unzip -q "$archive" -d "$jadx_dir"
        find "$jadx_dir/bin" -type f -exec chmod +x {} +
        printf '%s\n' "$JADX_SHA256_EXPECTED" > "$jadx_marker"
        chmod 0644 "$jadx_marker"
        rm -f "$archive"
        log "jadx instalado en $jadx_dir"
    fi
    clone_fixed "https://github.com/pxb1988/dex2jar.git" "$TOOLS_DIR/dex2jar" "$DEX2JAR_COMMIT"
}

clone_fixed() {
    local url="$1" dest="$2" revision="$3"
    validate_path "$dest"
    if [[ -d "$dest/.git" ]]; then
        local current
        current="$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)"
        [[ "$current" == "$revision" ]] || fail "repositorio existente con revisión inesperada: $dest"
        log "Repositorio existente en revisión fijada: $dest"
    elif [[ -e "$dest" && -n "$(find "$dest" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        fail "destino no vacío y no es un clone controlado: $dest"
    else
        run git -c protocol.version=2 init --quiet "$dest"
        run git -C "$dest" remote add origin "$url"
        run git -C "$dest" fetch --quiet --depth 1 origin "$revision"
        run git -C "$dest" checkout --quiet --detach FETCH_HEAD
    fi
}

python_tools() {
    if (( DRY_RUN )); then
        run python3 -m pip install --user --require-hashes --requirement "$ROOT_DIR/requirements.lock"
    else
        python3 -m pip install --user --require-hashes --requirement "$ROOT_DIR/requirements.lock"
    fi
    log "Herramientas Python instaladas para el usuario actual; usa $HOME/.local/bin en PATH"
}

install_static() {
    log "[4/6] Detección de comportamiento malicioso (análisis estático)"
    python_tools
    clone_fixed "https://github.com/MobSF/Mobile-Security-Framework-MobSF.git" "$TOOLS_DIR/MobSF" "$MOBSF_COMMIT"
    log "MobSF queda preparado; ejecuta setup/run manualmente en el laboratorio"
}

install_dynamic() {
    log "[5/6] Análisis dinámico e instrumentación en vivo"
    python_tools
    log "objection se conecta a una app autorizada en ejecución mediante Frida; no se adjunta a dispositivos automáticamente"
}

install_traffic() {
    log "[6/6] Captura y análisis de tráfico de red"
    if (( ! SKIP_APT )); then sudo_run apt-get install -y wireshark tcpdump; fi
    local user_name="${SUDO_USER:-${USER:-$(id -un)}}"
    if (( ! DRY_RUN )); then sudo_run usermod -aG wireshark "$user_name" || log "no se pudo añadir $user_name al grupo wireshark"; fi
    python_tools
    log "mitmproxy queda disponible normalmente en $HOME/.local/bin/mitmproxy"
}

summary() {
    cat <<EOF

==================================================================
 Instalación completa / plan ejecutado. Herramientas:

 ESTÁTICO: apktool, jadx, dex2jar, androguard, quark-engine, apkid, MobSF
 DINÁMICO: adb, frida-tools, objection, mitmproxy, wireshark, tcpdump
 Python user scripts: $HOME/.local/bin
 Manuales/clones: $TOOLS_DIR
==================================================================
EOF
}

run_traces() {
    local -a args=(bash "$ROOT_DIR/src/android_toolchain/traces.sh")
    [[ -n "$TRACES_SERIAL" ]] && args+=(--serial "$TRACES_SERIAL")
    [[ -n "$TRACES_DIR" ]] && args+=(--out-dir "$TRACES_DIR")
    [[ -n "$TRACES_SOURCES" ]] && args+=(--sources "$TRACES_SOURCES")
    [[ -n "$SCOPE_FILE" ]] && args+=(--scope-file "$SCOPE_FILE")
    (( DRY_RUN )) && args+=(--dry-run)
    (( PLAN_JSON )) && args+=(--plan-json)
    (( TRACES_CONFIRM )) && args+=(--confirm)
    "${args[@]}"
}

run_audit() {
    local -a args=(bash "$ROOT_DIR/src/android_toolchain/audit.sh")
    [[ -n "$AUDIT_SERIAL" ]] && args+=(--serial "$AUDIT_SERIAL")
    [[ -n "$AUDIT_DIR" ]] && args+=(--out-dir "$AUDIT_DIR")
    [[ -n "$AUDIT_CHECKS" ]] && args+=(--checks "$AUDIT_CHECKS")
    [[ -n "$AUDIT_EXPECTED_KEY" ]] && args+=(--expected-key "$AUDIT_EXPECTED_KEY")
    [[ -n "$AUDIT_SEED" ]] && args+=(--seed "$AUDIT_SEED")
    (( AUDIT_NO_NETWORK_PROBE )) && args+=(--sin-sonda-red)
    [[ -n "$SCOPE_FILE" ]] && args+=(--scope-file "$SCOPE_FILE")
    (( DRY_RUN )) && args+=(--dry-run)
    (( PLAN_JSON )) && args+=(--plan-json)
    (( AUDIT_CONFIRM )) && args+=(--confirm)
    "${args[@]}"
}

run_connect() {
    local -a args=(bash "$ROOT_DIR/src/android_toolchain/connect.sh")
    [[ -n "$CONNECT_SERIAL" ]] && args+=(--serial "$CONNECT_SERIAL")
    [[ -n "$CONNECT_DIR" ]] && args+=(--out-dir "$CONNECT_DIR")
    [[ -n "$CONNECT_TCP" ]] && args+=(--tcp "$CONNECT_TCP")
    (( CONNECT_FORCE )) && args+=(--force)
    [[ -n "$CONNECT_TIMEOUT" ]] && args+=(--timeout "$CONNECT_TIMEOUT")
    [[ -n "$SCOPE_FILE" ]] && args+=(--scope-file "$SCOPE_FILE")
    (( DRY_RUN )) && args+=(--dry-run)
    (( PLAN_JSON )) && args+=(--plan-json)
    (( CONNECT_CONFIRM )) && args+=(--confirm)
    "${args[@]}"
}

run_analyze() {
    local -a args=(python3 "$ROOT_DIR/src/android_toolchain/analyze_traces.py")
    [[ -n "$ANALYZE_DIR" ]] && args+=(--dir "$ANALYZE_DIR")
    local f
    for f in "${ANALYZE_FILES[@]}"; do args+=(--file "$f"); done
    [[ -n "$ANALYZE_OUT_DIR" ]] && args+=(--out-dir "$ANALYZE_OUT_DIR")
    [[ -n "$ANALYZE_MAX_MUESTRAS" ]] && args+=(--max-muestras "$ANALYZE_MAX_MUESTRAS")
    (( DRY_RUN )) && args+=(--dry-run)
    (( PLAN_JSON )) && args+=(--plan-json)
    if (( ANALYZE_PEDIR_BUGREPORT )); then
        (( DRY_RUN )) || (( ANALYZE_CONFIRM )) \
            || fail "--analyze-pedir-bugreport exige --analyze-confirm o --dry-run"
        # Alcance: el serial pedido debe estar autorizado.
        source "$ROOT_DIR/src/android_toolchain/scope.sh"
        local scope_eff
        scope_eff="$(scope_file_effective "$SCOPE_FILE")"
        if [[ -n "$SCOPE_FILE" && ! -f "$SCOPE_FILE" ]]; then
            fail "archivo de alcance no encontrado: $SCOPE_FILE"
        fi
        scope_check_serial "$scope_eff" "$ANALYZE_SERIAL"
        local out_dir="${ANALYZE_OUT_DIR:-$HOME/security-tools/analyses}"
        local fecha; fecha="$(date +%Y%m%d-%H%M%S)"
        local zip="$out_dir/bugreport-${fecha}_${ANALYZE_SERIAL:-todos}.zip"
        local timeout="${ANALYZE_TIMEOUT:-300}"
        if (( DRY_RUN )); then
            local adb_cmd="adb bugreport"
            [[ -n "$ANALYZE_SERIAL" ]] && adb_cmd="adb -s $ANALYZE_SERIAL bugreport"
            printf 'PLAN DE PETICIÓN DE BUGREPORT (dry-run, sin cambios)\n'
            printf 'Versión: %s | serial: %s | timeout: %s s | salida: %s\n' \
                "$VERSION" "${ANALYZE_SERIAL:-único dispositivo}" "$timeout" "$zip"
            printf '  + %s %s\n' "$adb_cmd" "$zip"
            printf '  + analizar el zip con analyze_traces.py\n'
            return 0
        fi
        if (( PLAN_JSON )); then
            printf '{"version": "%s", "pedir_bugreport": true, "serial": "%s", "timeout": %s, "salida": "%s"}\n' \
                "$VERSION" "$ANALYZE_SERIAL" "$timeout" "$zip"
            return 0
        fi
        command -v adb >/dev/null 2>&1 || fail "adb no está instalado"
        # Estado del dispositivo: el serial debe estar en `device`.
        local devices_line
        devices_line="$(adb devices 2>/dev/null | tail -n +2)"
        local state=""
        if [[ -n "$ANALYZE_SERIAL" ]]; then
            state="$(printf '%s\n' "$devices_line" | awk -v s="$ANALYZE_SERIAL" '$1==s {print $2}')"
            [[ -n "$state" ]] || fail "dispositivo no visible en adb devices: $ANALYZE_SERIAL"
            [[ "$state" == "device" ]] || fail "dispositivo no autorizado o fuera de línea: $ANALYZE_SERIAL ($state)"
        else
            local count
            count="$(printf '%s\n' "$devices_line" | grep -c $'\tdevice$' || true)"
            (( count == 1 )) || fail "sin --analyze-serial se exige un único dispositivo en estado device (hay $count)"
            ANALYZE_SERIAL="$(printf '%s\n' "$devices_line" | awk '$2=="device" {print $1; exit}')"
            zip="$out_dir/bugreport-${fecha}_${ANALYZE_SERIAL}.zip"
        fi
        mkdir -p "$out_dir"
        printf 'Pidiendo bugreport a %s (puede tardar unos minutos)...\n' "$ANALYZE_SERIAL"
        if ! timeout "$timeout" adb -s "$ANALYZE_SERIAL" bugreport "$zip"; then
            fail "no se pudo pedir el bugreport a $ANALYZE_SERIAL"
        fi
        [[ -s "$zip" ]] || fail "el bugreport llegó vacío: $zip"
        printf 'Bugreport guardado: %s\n' "$zip"
        args+=(--file "$zip")
    fi
    "${args[@]}"
}

run_apps() {
    local -a args=(bash "$ROOT_DIR/src/android_toolchain/apps.sh")
    [[ -n "$APPS_SERIAL" ]] && args+=(--serial "$APPS_SERIAL")
    [[ -n "$APPS_DIR" ]] && args+=(--out-dir "$APPS_DIR")
    (( APPS_TODAS )) && args+=(--todas)
    [[ -n "$SCOPE_FILE" ]] && args+=(--scope-file "$SCOPE_FILE")
    (( DRY_RUN )) && args+=(--dry-run)
    (( PLAN_JSON )) && args+=(--plan-json)
    (( APPS_CONFIRM )) && args+=(--confirm)
    "${args[@]}"
}

android_toolchain_main() {
    while (($#)); do
        case "$1" in
            --tools-dir) (($# >= 2)) || fail "--tools-dir requiere PATH"; TOOLS_DIR="$2"; shift 2 ;;
            --dry-run) DRY_RUN=1; shift ;;
            --plan-json) PLAN_JSON=1; shift ;;
            --static-only) STATIC_ONLY=1; shift ;;
            --dynamic-only) DYNAMIC_ONLY=1; shift ;;
            --skip-apt) SKIP_APT=1; shift ;;
            --banner-style) (($# >= 2)) || fail "--banner-style requiere 0, 1 o 2"; BANNER_STYLE="$2"; shift 2 ;;
            --interactive) INTERACTIVE=1; shift ;;
            --guided) GUIDED=1; shift ;;
            --traces) TRACES_ONLY=1; shift ;;
            --traces-serial|--serial) (($# >= 2)) || fail "--traces-serial requiere SERIAL"; TRACES_SERIAL="$2"; AUDIT_SERIAL="$2"; CONNECT_SERIAL="$2"; ANALYZE_SERIAL="$2"; APPS_SERIAL="$2"; shift 2 ;;
            --traces-dir) (($# >= 2)) || fail "--traces-dir requiere PATH"; TRACES_DIR="$2"; shift 2 ;;
            --traces-sources) (($# >= 2)) || fail "--traces-sources requiere LISTA"; TRACES_SOURCES="$2"; shift 2 ;;
            --traces-confirm) TRACES_CONFIRM=1; shift ;;
            --audit) AUDIT_ONLY=1; shift ;;
            --audit-serial) (($# >= 2)) || fail "--audit-serial requiere SERIAL"; AUDIT_SERIAL="$2"; shift 2 ;;
            --audit-dir) (($# >= 2)) || fail "--audit-dir requiere PATH"; AUDIT_DIR="$2"; shift 2 ;;
            --audit-checks) (($# >= 2)) || fail "--audit-checks requiere LISTA"; AUDIT_CHECKS="$2"; shift 2 ;;
            --audit-expected-key) (($# >= 2)) || fail "--audit-expected-key requiere PATH"; AUDIT_EXPECTED_KEY="$2"; shift 2 ;;
            --audit-seed) (($# >= 2)) || fail "--audit-seed requiere N"; AUDIT_SEED="$2"; shift 2 ;;
            --audit-sin-sonda-red) AUDIT_NO_NETWORK_PROBE=1; shift ;;
            --audit-confirm) AUDIT_CONFIRM=1; shift ;;
            --connect) CONNECT_ONLY=1; shift ;;
            --connect-serial) (($# >= 2)) || fail "--connect-serial requiere SERIAL"; CONNECT_SERIAL="$2"; shift 2 ;;
            --connect-dir) (($# >= 2)) || fail "--connect-dir requiere PATH"; CONNECT_DIR="$2"; shift 2 ;;
            --connect-tcp) (($# >= 2)) || fail "--connect-tcp requiere IP[:PUERTO]"; CONNECT_TCP="$2"; shift 2 ;;
            --connect-force) CONNECT_FORCE=1; shift ;;
            --connect-timeout) (($# >= 2)) || fail "--connect-timeout requiere N"; CONNECT_TIMEOUT="$2"; shift 2 ;;
            --connect-confirm) CONNECT_CONFIRM=1; shift ;;
            --analyze) ANALYZE_ONLY=1; shift ;;
            --analyze-dir) (($# >= 2)) || fail "--analyze-dir requiere DIR"; ANALYZE_DIR="$2"; shift 2 ;;
            --analyze-file) (($# >= 2)) || fail "--analyze-file requiere ARCHIVO"; ANALYZE_FILES+=("$2"); shift 2 ;;
            --analyze-out-dir) (($# >= 2)) || fail "--analyze-out-dir requiere PATH"; ANALYZE_OUT_DIR="$2"; shift 2 ;;
            --analyze-pedir-bugreport) ANALYZE_PEDIR_BUGREPORT=1; shift ;;
            --analyze-serial) (($# >= 2)) || fail "--analyze-serial requiere SERIAL"; ANALYZE_SERIAL="$2"; shift 2 ;;
            --analyze-timeout) (($# >= 2)) || fail "--analyze-timeout requiere N"; ANALYZE_TIMEOUT="$2"; shift 2 ;;
            --analyze-max-muestras) (($# >= 2)) || fail "--analyze-max-muestras requiere N"; ANALYZE_MAX_MUESTRAS="$2"; shift 2 ;;
            --analyze-confirm) ANALYZE_CONFIRM=1; shift ;;
            --apps) APPS_ONLY=1; shift ;;
            --apps-serial) (($# >= 2)) || fail "--apps-serial requiere SERIAL"; APPS_SERIAL="$2"; shift 2 ;;
            --apps-dir) (($# >= 2)) || fail "--apps-dir requiere PATH"; APPS_DIR="$2"; shift 2 ;;
            --apps-todas) APPS_TODAS=1; shift ;;
            --apps-confirm) APPS_CONFIRM=1; shift ;;
            --scope-file) (($# >= 2)) || fail "--scope-file requiere PATH"; SCOPE_FILE="$2"; shift 2 ;;
            -h|--help) usage; return 0 ;;
            *) fail "opción desconocida: $1" ;;
        esac
    done

    (( STATIC_ONLY && DYNAMIC_ONLY )) && fail "--static-only y --dynamic-only son excluyentes"
    (( TRACES_ONLY && AUDIT_ONLY )) && fail "--traces y --audit son excluyentes"
    (( TRACES_ONLY && CONNECT_ONLY )) && fail "--traces y --connect son excluyentes"
    (( AUDIT_ONLY && CONNECT_ONLY )) && fail "--audit y --connect son excluyentes"
    (( TRACES_ONLY && ANALYZE_ONLY )) && fail "--traces y --analyze son excluyentes"
    (( AUDIT_ONLY && ANALYZE_ONLY )) && fail "--audit y --analyze son excluyentes"
    (( CONNECT_ONLY && ANALYZE_ONLY )) && fail "--connect y --analyze son excluyentes"
    (( TRACES_ONLY && APPS_ONLY )) && fail "--traces y --apps son excluyentes"
    (( AUDIT_ONLY && APPS_ONLY )) && fail "--audit y --apps son excluyentes"
    (( CONNECT_ONLY && APPS_ONLY )) && fail "--connect y --apps son excluyentes"
    (( ANALYZE_ONLY && APPS_ONLY )) && fail "--analyze y --apps son excluyentes"
    if (( TRACES_ONLY )); then
        (( STATIC_ONLY || DYNAMIC_ONLY )) && fail "--traces no se combina con --static-only ni --dynamic-only"
        run_traces
        return $?
    fi
    if (( AUDIT_ONLY )); then
        (( STATIC_ONLY || DYNAMIC_ONLY )) && fail "--audit no se combina con --static-only ni --dynamic-only"
        run_audit
        return $?
    fi
    if (( CONNECT_ONLY )); then
        (( STATIC_ONLY || DYNAMIC_ONLY )) && fail "--connect no se combina con --static-only ni --dynamic-only"
        run_connect
        return $?
    fi
    if (( ANALYZE_ONLY )); then
        (( STATIC_ONLY || DYNAMIC_ONLY )) && fail "--analyze no se combina con --static-only ni --dynamic-only"
        run_analyze
        return $?
    fi
    if (( APPS_ONLY )); then
        (( STATIC_ONLY || DYNAMIC_ONLY )) && fail "--apps no se combina con --static-only ni --dynamic-only"
        run_apps
        return $?
    fi
    validate_style
    validate_checksum
    validate_path "$TOOLS_DIR"
    if [[ "$TOOLS_DIR" != /* ]]; then TOOLS_DIR="$PWD/$TOOLS_DIR"; fi
    TOOLS_DIR="$(realpath -m -- "$TOOLS_DIR")"
    if (( GUIDED )); then
        banner
        guided_flow
        return 0
    fi
    if (( INTERACTIVE )); then
        interactive_select
        (( STATIC_ONLY && DYNAMIC_ONLY )) && fail "selección de fases incompatible"
    fi
    if (( PLAN_JSON )); then plan_json; return 0; fi
    if (( ! DRY_RUN )); then mkdir -p "$TOOLS_DIR"; fi

    banner
    if (( DYNAMIC_ONLY == 0 )); then
        flow_transition "base-adb-static"
        install_base
        install_adb
        install_apk_tools
        install_static
    fi
    if (( STATIC_ONLY == 0 )); then
        flow_transition "dynamic-traffic"
        (( DYNAMIC_ONLY )) && { install_base; install_adb; }
        install_dynamic
        install_traffic
    fi
    summary
}
