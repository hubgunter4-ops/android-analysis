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

Variables:
  JADX_SHA256             Compatibilidad: solo se acepta el SHA-256 fijado de JADX ${JADX_VERSION}.
  TOOLS_DIR               Igual que --tools-dir.

Ejemplos:
  ./src/no4nn.sh --dry-run --static-only
  ./src/no4nn.sh --plan-json --dynamic-only --tools-dir /opt/security-tools
  sudo -E ./src/no4nn.sh --tools-dir "$HOME/security-tools" --banner-style 1
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
            -h|--help) usage; return 0 ;;
            *) fail "opción desconocida: $1" ;;
        esac
    done

    (( STATIC_ONLY && DYNAMIC_ONLY )) && fail "--static-only y --dynamic-only son excluyentes"
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
