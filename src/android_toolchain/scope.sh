#!/usr/bin/env bash
#
# Alcance de laboratorio — lista de permitidos (allowlist) para los
# scripts de android-analysis. Es una biblioteca: se carga con
# `source scope.sh` desde el mismo directorio del script que la usa.
#
# Formato del archivo de alcance (por defecto $HOME/security-tools/scope):
#   # comentarios con # y líneas vacías se ignoran
#   serial:emulator-5554        un serial autorizado
#   tcp:192.168.1.42            una IP autorizada para adb connect
#   tcp:192.168.1.0/24          una red autorizada (CIDR)
#
# Reglas:
# - Si el archivo no existe, no hay enforcement: se anota en el
#   reporte que no hay archivo de alcance y el operador responde por
#   el objetivo. Crear el archivo activa la allowlist.
# - Si el archivo existe y tiene entradas `serial:`, un serial dado
#   debe estar listado; sin entradas `serial:` no se restringe el serial.
# - Si el archivo existe y se pide TCP, la IP debe estar listada
#   (exacta o dentro de una red CIDR); sin entradas `tcp:`, TCP no
#   está autorizado.
# - `fail` la define el script que carga esta biblioteca; si no
#   existe, se define aquí una versión mínima.

SCOPE_FILE_DEFAULT="${HOME}/security-tools/scope"

if ! declare -F fail >/dev/null 2>&1; then
    fail() {
        printf 'Error: %s\n' "$*" >&2
        exit 2
    }
fi

# Devuelve la ruta efectiva del archivo de alcance: la explícita si
# se pasó una, o la ruta por defecto si el archivo existe.
scope_file_effective() {
    local explicit="${1:-}"
    if [[ -n "$explicit" ]]; then
        printf '%s\n' "$explicit"
    elif [[ -f "$SCOPE_FILE_DEFAULT" ]]; then
        printf '%s\n' "$SCOPE_FILE_DEFAULT"
    else
        printf '%s\n' ""
    fi
}

# Resumen de una línea para reportes y GUI.
scope_status() {
    local file="$1"
    if [[ -z "$file" ]]; then
        printf 'sin archivo de alcance (allowlist inactiva; el operador responde por el objetivo)'
        return 0
    fi
    if [[ ! -f "$file" ]]; then
        printf 'archivo de alcance no encontrado: %s' "$file"
        return 0
    fi
    local serials tcps
    serials="$(grep -c '^serial:' "$file" 2>/dev/null || true)"
    tcps="$(grep -c '^tcp:' "$file" 2>/dev/null || true)"
    printf 'alcance: %s (%s serial(es), %s entrada(s) TCP)' "$file" "$serials" "$tcps"
}

# Valida la ruta del archivo de alcance (sin traversal, caracteres seguros).
scope_validate_path() {
    local path="$1"
    [[ -n "$path" ]] || return 0
    [[ "$path" =~ ^[A-Za-z0-9_./:@+,-]+$ ]] || fail "ruta de alcance no válida; usa solo caracteres de ruta seguros"
    local part
    IFS='/' read -r -a _scope_parts <<< "$path"
    for part in "${_scope_parts[@]}"; do
        [[ "$part" != .. ]] || fail "ruta de alcance con traversal no permitida"
    done
}

# ¿La IP está dentro de la red CIDR? Solo IPv4.
_ip_in_cidr() {
    local ip="$1" cidr="$2"
    local net prefix
    net="${cidr%%/*}"
    prefix="${cidr##*/}"
    [[ "$prefix" =~ ^[0-9]+$ ]] && (( prefix >= 0 && prefix <= 32 )) || return 1
    local -a ip_oct net_oct
    IFS='.' read -r -a ip_oct <<< "$ip"
    IFS='.' read -r -a net_oct <<< "$net"
    (( ${#ip_oct[@]} == 4 && ${#net_oct[@]} == 4 )) || return 1
    local mask=$(( prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    local ip_n=$(( (ip_oct[0] << 24) | (ip_oct[1] << 16) | (ip_oct[2] << 8) | ip_oct[3] ))
    local net_n=$(( (net_oct[0] << 24) | (net_oct[1] << 16) | (net_oct[2] << 8) | net_oct[3] ))
    (( (ip_n & mask) == (net_n & mask) ))
}

# Comprueba un serial contra la allowlist. Falla si está fuera de alcance.
scope_check_serial() {
    local file="$1" serial="$2"
    [[ -z "$serial" ]] && return 0
    [[ -n "$file" && -f "$file" ]] || return 0
    local count
    count="$(grep -c '^serial:' "$file" 2>/dev/null || true)"
    (( count == 0 )) && return 0
    grep -qxF "serial:$serial" "$file" \
        || fail "serial fuera del alcance de laboratorio: $serial (revisa $file)"
}

# Comprueba una IP contra la allowlist TCP. Falla si está fuera de alcance.
scope_check_tcp() {
    local file="$1" ip="$2"
    [[ -n "$file" && -f "$file" ]] || return 0
    local entry value
    while IFS= read -r entry; do
        value="${entry#tcp:}"
        if [[ "$value" == */* ]]; then
            _ip_in_cidr "$ip" "$value" && return 0
        elif [[ "$value" == "$ip" ]]; then
            return 0
        fi
    done < <(grep '^tcp:' "$file" 2>/dev/null || true)
    fail "IP fuera del alcance de laboratorio para TCP: $ip (revisa $file)"
}

# Plantilla del archivo de alcance (la GUI la escribe con confirmación).
scope_template() {
    cat <<'EOF'
# Alcance de laboratorio — android-analysis
# Solo estos objetivos están autorizados. Edita este archivo para
# añadir o quitar dispositivos y redes; sin él, la allowlist está
# inactiva y el operador responde por cada objetivo.
#
# Un serial autorizado por línea:
# serial:emulator-5554
#
# Una IP o red autorizada para adb connect por línea:
# tcp:192.168.1.42
# tcp:192.168.1.0/24
EOF
}
