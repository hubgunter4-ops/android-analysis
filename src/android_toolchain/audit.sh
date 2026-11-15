#!/usr/bin/env bash
#
# Auditoría ADB — claves RSA autorizadas, propiedades de depuración,
# exposición en red y puerto TCP 5555, antes de cualquier conexión.
# Solo sobre un dispositivo de laboratorio autorizado, con
# confirmación explícita, y guarda cada comprobación en su propio
# archivo bajo un directorio de evidencia fuera del árbol del proyecto.
#
# La auditoría no conecta ningún dispositivo: verifica que el serial
# indicado ya aparezca como `device` en `adb devices` y lee el estado
# del dispositivo por adb. La única sonda de red es un intento TCP
# (SYN) contra el puerto 5555 de las IP del propio dispositivo, sin
# iniciar sesión ADB; se puede omitir con --sin-sonda-red.
#
# Aleatorización: el orden de las comprobaciones se baraja con una
# semilla (--seed; por defecto aleatoria), hay una pausa aleatoria
# entre comprobaciones (0,2–1,5 s), el timeout de la sonda al 5555 es
# aleatorio (2–5 s) y el orden de las IP sondeadas también se baraja.
# Con la misma semilla, el plan y la ejecución usan el mismo orden.
# Las claves RSA y los logs pueden contener datos sensibles:
# trátalos como material sensible y consérvalos solo según la
# autorización.

set -Eeuo pipefail
IFS=$'\n\t'

AUDIT_VERSION="2.1.0"
OUT_DIR="${OUT_DIR:-$HOME/security-tools/audits}"
SERIAL=""
CHECKS=""
EXPECTED_KEY=""
SEED=""
NO_NETWORK_PROBE=0
DRY_RUN=0
PLAN_JSON=0
CONFIRM=0

# Comprobaciones conocidas. El orden real se baraja con la semilla.
KNOWN_CHECKS=(claves-rsa propiedades-depuracion exposicion-red puerto-5555 fuga-datos apps-terceros)
DEFAULT_CHECKS="claves-rsa,propiedades-depuracion,exposicion-red,puerto-5555,fuga-datos,apps-terceros"

# Propiedades de depuración que se leen con getprop.
PROPS=(ro.debuggable ro.secure ro.adb.secure service.adb.tcp.port persist.adb.tcp.port sys.usb.config persist.sys.usb.config ro.build.type ro.build.tags ro.product.model ro.build.version.release)

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 2
}

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

usage() {
    cat <<'EOF'
Uso: audit.sh [opciones]

  --serial SERIAL        Serial del dispositivo (verificado en `adb devices`).
                         Sin serial se exige exactamente un dispositivo `device`.
  --out-dir PATH         Directorio base de evidencia (default: $HOME/security-tools/audits).
                         Cada auditoría crea <out-dir>/AUDITORIA-AAAAMMDD-HHMMSS_<serial>/.
  --checks LISTA         Comprobaciones separadas por coma (default: las seis).
                         Valores: claves-rsa, propiedades-depuracion, exposicion-red, puerto-5555,
                         fuga-datos, apps-terceros.
  --expected-key PATH    Clave pública del operador (.pub) para contrastar las
                         claves autorizadas (default: $HOME/.android/adbkey.pub si existe).
  --seed N               Semilla entera de la aleatorización (orden, pausas, timeout
                         de sonda). Sin ella se genera una aleatoria por ejecución.
  --sin-sonda-red        Omite la sonda TCP desde la red al puerto 5555; solo se
                         comprueba el estado del puerto dentro del dispositivo.
  --dry-run              Muestra el plan; no llama a adb ni crea directorios.
  --plan-json            Emite el plan como JSON y no ejecuta la auditoría.
  --confirm              Confirmación explícita para una auditoría real.
                         Sin --dry-run ni --confirm la auditoría se rechaza.
  -h, --help             Muestra esta ayuda.

Ejemplos:
  ./src/android_toolchain/audit.sh --dry-run
  ./src/android_toolchain/audit.sh --dry-run --serial emulator-5554
  ./src/android_toolchain/audit.sh --plan-json --checks claves-rsa,puerto-5555
  ./src/android_toolchain/audit.sh --serial emulator-5554 --confirm
  ./src/android_toolchain/audit.sh --serial emulator-5554 --confirm --seed 42
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

validate_checks() {
    local check known
    IFS=',' read -r -a wanted <<< "$CHECKS"
    for check in "${wanted[@]}"; do
        known=0
        for candidate in "${KNOWN_CHECKS[@]}"; do
            [[ "$check" == "$candidate" ]] && known=1
        done
        (( known )) || fail "comprobación desconocida: $check"
    done
}

validate_seed() {
    [[ -z "$SEED" || "$SEED" =~ ^[0-9]+$ ]] || fail "la semilla debe ser un entero no negativo"
}

# argv base de adb, sin shell: serial opcional.
adb_args() {
    if [[ -n "$SERIAL" ]]; then printf '%s\n' "adb" "-s" "$SERIAL"; else printf '%s\n' "adb"; fi
}

# Nombre de archivo para cada comprobación.
file_for_check() {
    case "$1" in
        claves-rsa) printf '01-claves-rsa-autorizadas.txt' ;;
        propiedades-depuracion) printf '02-propiedades-depuracion.txt' ;;
        exposicion-red) printf '03-exposicion-red.txt' ;;
        puerto-5555) printf '04-puerto-5555.txt' ;;
        fuga-datos) printf '05-fuga-datos-sensibles.txt' ;;
        apps-terceros) printf '06-apps-terceros-depurables.txt' ;;
    esac
}

# Descripción legible de cada comprobación.
describe_check() {
    case "$1" in
        claves-rsa) printf 'Claves RSA autorizadas en el dispositivo (/data/misc/adb/adb_keys)' ;;
        propiedades-depuracion) printf 'Propiedades de depuración (getprop)' ;;
        exposicion-red) printf 'Exposición en red (interfaces, rutas y puertos en escucha)' ;;
        puerto-5555) printf 'Puerto TCP 5555 en escucha (estado interno + sonda de red)' ;;
        fuga-datos) printf 'Fuga de datos sensibles en registros (tokens, contraseñas, PII)' ;;
        apps-terceros) printf 'Apps de terceros y cuáles son depurables (pm + dumpsys package)' ;;
    esac
}

# Semilla efectiva: la indicada, o una aleatoria derivada del proceso.
effective_seed() {
    if [[ -n "$SEED" ]]; then printf '%s' "$SEED"; return; fi
    printf '%s' "$(( (RANDOM ^ $$ ^ $(date +%s%N | cut -c1-9)) & 0x7fffffff ))"
}

# Orden barajado (Fisher-Yates) de las comprobaciones pedidas, con la
# semilla efectiva. Se imprime una por línea.
shuffled_checks() {
    local seed="$1"
    RANDOM="$seed"
    local -a items
    IFS=',' read -r -a items <<< "$CHECKS"
    local i j tmp
    for (( i = ${#items[@]} - 1; i > 0; i-- )); do
        j=$(( RANDOM % (i + 1) ))
        tmp="${items[$i]}"; items[$i]="${items[$j]}"; items[$j]="$tmp"
    done
    printf '%s\n' "${items[@]}"
}

# Pausa aleatoria entre comprobaciones (0,2–1,5 s). Solo en ejecuciones reales.
jitter() {
    local ms=$(( 200 + RANDOM % 1301 ))
    local sec=$(( ms / 1000 )) rem=$(( ms % 1000 ))
    sleep "$sec.$(printf '%03d' "$rem")"
}

# Huella SHA-256 de una clave (su blob base64).
key_fingerprint() {
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
}

# Comando adb principal de cada comprobación, para el plan.
command_for_check() {
    local -a base
    mapfile -t base < <(adb_args)
    case "$1" in
        claves-rsa) printf '%q ' "${base[@]}" shell cat /data/misc/adb/adb_keys; printf '\n' ;;
        propiedades-depuracion)
            printf '%q ' "${base[@]}" shell getprop; printf '(una llamada por propiedad: %s)\n' "$(IFS=,; echo "${PROPS[*]}")"
            ;;
        exposicion-red)
            printf '%q ' "${base[@]}" shell ip addr show; printf '; '
            printf '%q ' "${base[@]}" shell ss -tlnp; printf '(fallback netstat, luego /proc/net/tcp)\n'
            ;;
        puerto-5555)
            printf '%q ' "${base[@]}" shell cat /proc/net/tcp /proc/net/tcp6; printf '; sonda TCP a <IP del dispositivo>:5555'
            (( NO_NETWORK_PROBE )) && printf ' [omitida con --sin-sonda-red]'
            printf '\n'
            ;;
        fuga-datos)
            printf '%q ' "${base[@]}" logcat -d -v threadtime -b main -b system -b events -b crash
            printf ' (el registro crudo NO se guarda: solo conteos y muestras redactadas)\n'
            ;;
        apps-terceros)
            printf '%q ' "${base[@]}" shell pm list packages -3; printf '; '
            printf '%q ' "${base[@]}" shell dumpsys package; printf ' (se cruza con la lista de terceros)\n'
            ;;
    esac
}

# Ejecuta una comprobación y registra su veredicto en los arrays globales.
# Un fallo en una comprobación no aborta el resto.
declare -a DONE_CHECKS=() DONE_FILES=() DONE_CODES=() DONE_DESCS=() DONE_VERDICTS=()
run_check() {
    local check="$1" file="$2"
    local -a base
    mapfile -t base < <(adb_args)
    local code=0 verdict="OK"
    log "auditando $check -> $file"

    case "$check" in
        claves-rsa)
            local keys_ok=0
            if "${base[@]}" shell cat /data/misc/adb/adb_keys >"$file" 2>"$file.err"; then
                keys_ok=1
            else
                log "adb_keys no legible directamente; intentando con su (timeout 10 s)"
                if timeout 10 "${base[@]}" shell su -c 'cat /data/misc/adb/adb_keys' >"$file" 2>"$file.err"; then
                    keys_ok=1
                fi
            fi
            if (( keys_ok )); then
                local expected_blob="" key_count=0 unknown=0
                if [[ -n "$EXPECTED_KEY" && -f "$EXPECTED_KEY" ]]; then
                    expected_blob="$(awk '{print $1}' "$EXPECTED_KEY" | head -n 1)"
                fi
                # Se lee el contenido en memoria primero: el análisis se
                # añade al mismo archivo y no debe realimentar el bucle.
                local -a key_lines
                mapfile -t key_lines <"$file"
                {
                    printf '\n== ANÁLISIS ==\n'
                    printf 'clave del operador: %s\n' "${EXPECTED_KEY:-<sin clave del operador para contrastar>}"
                    local line blob comment fp status
                    for line in "${key_lines[@]}"; do
                        [[ -z "$line" ]] && continue
                        key_count=$((key_count + 1))
                        blob="${line%% *}"
                        comment="${line#* }"
                        fp="$(key_fingerprint "$blob")"
                        if [[ -n "$expected_blob" ]]; then
                            if [[ "$blob" == "$expected_blob" ]]; then status="COINCIDE con la clave del operador"; else status="DESCONOCIDA"; unknown=$((unknown + 1)); fi
                        else
                            status="sin contraste (falta la clave del operador)"
                        fi
                        printf 'clave %d: SHA-256 %s | %s | %s\n' "$key_count" "$fp" "$status" "${comment:-<sin comentario>}"
                    done
                    printf 'total de claves autorizadas: %d\n' "$key_count"
                    if (( key_count == 0 )); then
                        printf 'sin claves autorizadas: ningún equipo puede conectar por USB sin volver a autorizar\n'
                        verdict="ADVERTENCIA"
                    elif [[ -n "$expected_blob" ]] && (( unknown > 0 )); then
                        printf 'HAY %d CLAVE(S) DESCONOCIDA(S) AUTORIZADA(S): revoca las que no reconozcas antes de conectar\n' "$unknown"
                        verdict="CRÍTICO"
                    elif [[ -z "$expected_blob" ]]; then
                        printf 'sin clave del operador no se puede distinguir una clave conocida de una desconocida\n'
                        verdict="ADVERTENCIA"
                    fi
                } >>"$file"
            else
                {
                    printf 'adb_keys no legible sin root: no se puede verificar qué equipos están autorizados\n'
                    printf 'repite la auditoría con un dispositivo rooteado o userdebug\n'
                } >>"$file"
                verdict="ADVERTENCIA"
                code=1
            fi
            ;;
        propiedades-depuracion)
            {
                local prop value
                for prop in "${PROPS[@]}"; do
                    value="$("${base[@]}" shell getprop "$prop" 2>/dev/null | tr -d '\r' || true)"
                    printf '%s=%s\n' "$prop" "${value:-<vacío>}"
                done
            } >"$file" 2>"$file.err" || code=$?
            {
                printf '\n== ANÁLISIS ==\n'
                local debuggable secure adb_secure tcp_port
                debuggable="$(grep -E '^ro\.debuggable=' "$file" | cut -d= -f2-)"
                secure="$(grep -E '^ro\.secure=' "$file" | cut -d= -f2-)"
                adb_secure="$(grep -E '^ro\.adb\.secure=' "$file" | cut -d= -f2-)"
                tcp_port="$(grep -E '^service\.adb\.tcp\.port=' "$file" | cut -d= -f2-)"
                [[ "$debuggable" == "1" ]] && { printf 'ro.debuggable=1: el sistema es depurable\n'; verdict="CRÍTICO"; }
                [[ "$secure" == "0" ]] && { printf 'ro.secure=0: adbd corre como root\n'; verdict="CRÍTICO"; }
                [[ "$tcp_port" == "5555" ]] && { printf 'service.adb.tcp.port=5555: ADB por TCP activado en el dispositivo\n'; verdict="CRÍTICO"; }
                [[ "$adb_secure" == "0" ]] && { printf 'ro.adb.secure=0: la autorización RSA está desactivada\n'; [[ "$verdict" != "CRÍTICO" ]] && verdict="ADVERTENCIA"; }
                grep -qE '^ro\.build\.type=(userdebug|eng)$' "$file" && { printf 'build userdebug/eng: depuración ampliada\n'; [[ "$verdict" != "CRÍTICO" ]] && verdict="ADVERTENCIA"; }
                [[ "$verdict" == "OK" ]] && printf 'sin indicadores de depuración activa\n'
            } >>"$file"
            ;;
        exposicion-red)
            {
                echo "== interfaces (ip addr show) =="
                if ! "${base[@]}" shell ip addr show; then
                    echo "ip no disponible; probando ifconfig"
                    "${base[@]}" shell ifconfig || echo "sin ip ni ifconfig"
                fi
                echo "== rutas (ip route) =="
                "${base[@]}" shell ip route || echo "sin rutas legibles"
                echo "== puertos TCP en escucha =="
                if ! "${base[@]}" shell ss -tlnp; then
                    echo "ss no disponible; probando netstat"
                    if ! "${base[@]}" shell netstat -tlnp; then
                        echo "sin ss ni netstat; puertos desde /proc/net/tcp"
                        "${base[@]}" shell cat /proc/net/tcp || echo "sin /proc/net/tcp"
                    fi
                fi
            } >"$file" 2>"$file.err" || code=$?
            {
                printf '\n== ANÁLISIS ==\n'
                # Puertos en escucha fuera de loopback, según ss/netstat o /proc/net/tcp.
                local listen
                listen="$(grep -E 'LISTEN|:0A' "$file" | grep -vE '127\.0\.0\.1|::1' || true)"
                if [[ -n "$listen" ]]; then
                    printf 'puertos TCP en escucha en interfaces no loopback:\n%s\n' "$listen"
                    verdict="ADVERTENCIA"
                else
                    printf 'sin puertos TCP en escucha fuera de loopback (o no determinable desde la salida)\n'
                fi
            } >>"$file"
            ;;
        puerto-5555)
            local listen_5555=0 probe_open=0 probe_done=0
            {
                echo "== estado interno (/proc/net/tcp y /proc/net/tcp6) =="
                local tcp_out tcp6_out
                tcp_out="$("${base[@]}" shell cat /proc/net/tcp 2>/dev/null || true)"
                tcp6_out="$("${base[@]}" shell cat /proc/net/tcp6 2>/dev/null || true)"
                printf '%s\n%s\n' "$tcp_out" "$tcp6_out"
                echo "== entradas en escucha (LISTEN, estado 0A) con puerto 15B3 (5555) =="
                # :15B3 es 5555 en hexadecimal; el campo 4 es el estado (0A = LISTEN).
                # La IP local viene en hexadecimal little-endian; 00000000 = todas las interfaces.
                local entries
                entries="$(printf '%s\n%s\n' "$tcp_out" "$tcp6_out" | awk '$2 ~ /:15B3$/ && $4 == "0A" {print $2}')"
                if [[ -n "$entries" ]]; then
                    listen_5555=1
                    printf '%s\n' "$entries"
                    if grep -qE '^(00000000|00000000000000000000000000000000):15B3$' <<<"$entries"; then
                        echo "5555 en escucha en TODAS las interfaces (0.0.0.0 / ::)"
                    else
                        echo "5555 en escucha solo en direcciones concretas (revisa si alguna no es loopback)"
                    fi
                else
                    echo "sin entradas 5555 en LISTEN en /proc/net/tcp*"
                fi
            } >"$file" 2>"$file.err" || code=$?
            if (( NO_NETWORK_PROBE )); then
                printf 'sonda de red omitida con --sin-sonda-red\n' >>"$file"
            else
                local probe_timeout=$(( 2 + RANDOM % 4 ))
                local -a ips
                mapfile -t ips < <("${base[@]}" shell ip -o -4 addr show 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}' | grep -v '^127\.0\.0\.1$' || true)
                # Baraja el orden de las IP sondeadas.
                local i j tmp
                for (( i = ${#ips[@]} - 1; i > 0; i-- )); do
                    j=$(( RANDOM % (i + 1) ))
                    tmp="${ips[$i]}"; ips[$i]="${ips[$j]}"; ips[$j]="$tmp"
                done
                {
                    printf '\n== sonda de red (timeout %d s por IP, orden aleatorio) ==\n' "$probe_timeout"
                    if (( ${#ips[@]} == 0 )); then
                        printf 'sin IP de red en el dispositivo; sonda omitida\n'
                    fi
                    local ip rc
                    for ip in "${ips[@]}"; do
                        probe_done=1
                        if timeout "$probe_timeout" bash -c "exec 3<>/dev/tcp/$ip/5555" 2>/dev/null; then
                            printf '%s:5555 ABIERTO (acepta conexiones TCP)\n' "$ip"
                            probe_open=1
                        else
                            rc=$?
                            if (( rc == 124 )); then printf '%s:5555 TIEMPO AGOTADO (filtrado o sin respuesta)\n' "$ip";
                            else printf '%s:5555 CERRADO (conexión rechazada)\n' "$ip"; fi
                        fi
                    done
                } >>"$file"
            fi
            {
                printf '\n== ANÁLISIS ==\n'
                if (( probe_open )); then
                    printf '5555 ACEPTA CONEXIONES DESDE LA RED: cualquiera en la misma red puede intentar ADB\n'
                    verdict="CRÍTICO"
                elif (( listen_5555 )); then
                    printf '5555 en escucha dentro del dispositivo (ver arriba si es en todas las interfaces)\n'
                    verdict="CRÍTICO"
                elif (( probe_done )); then
                    printf '5555 no acepta conexiones desde la red en las IP sondeadas\n'
                else
                    printf '5555 no aparece en escucha y no se pudo sondear desde la red\n'
                    [[ "$verdict" == "OK" ]] && verdict="ADVERTENCIA"
                fi
            } >>"$file"
            ;;
        fuga-datos)
            # El registro crudo NUNCA se guarda: puede contener los
            # secretos que se buscan. Se captura a un temporal 0600,
            # se cuentan las coincidencias por clase y se escriben
            # solo muestras redactadas (fecha, tag y clase; sin el
            # valor). El temporal se borra siempre.
            local raw_log
            raw_log="$(mktemp --tmpdir audit-logcat.XXXXXX)"
            chmod 0600 "$raw_log"
            if "${base[@]}" logcat -d -v threadtime -b main -b system -b events -b crash >"$raw_log" 2>"$file.err"; then
                code=0
            else
                code=$?
                log "ADVERTENCIA: logcat falló (código $code)"
            fi
            {
                printf 'Búsqueda de fuga de datos sensibles en logcat (main, system, events, crash)\n'
                printf 'El registro crudo NO se conserva: solo conteos por clase y muestras redactadas.\n\n'
                local class pattern count
                # Clase -> patrón (grep -iE). Los secretos no se imprimen jamás.
                local -a classes=(
                    "credenciales|password|passwd|pwd|api[_-]?key|secret|access[_-]?token|refresh[_-]?token|client[_-]?secret|authorization: *bearer|bearer [A-Za-z0-9._-]+"
                    "pii-correo|[A-Za-z0-9._%%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"
                    "pii-rfc-curp|[A-Z]{3,4}[0-9]{6}[A-Z0-9]{3}|[A-Z]{4}[0-9]{6}[HM][A-Z]{5}[0-9A-Z]{2}"
                )
                local credenciales=0 pii=0
                for entry in "${classes[@]}"; do
                    class="${entry%%|*}"
                    pattern="${entry#*|}"
                    count="$(grep -ciE "$pattern" "$raw_log" || true)"
                    printf '%-16s %s coincidencia(s)\n' "$class" "$count"
                    if (( count > 0 )); then
                        printf '  muestras redactadas (fecha, tag y clase; el valor no se guarda):\n'
                        grep -iE "$pattern" "$raw_log" | head -n 3 | while IFS= read -r line; do
                            # Fecha + hora + pid + tid + nivel + tag; el mensaje se sustituye.
                            local head
                            head="$(awk '{print $1, $2, $3, $4, $5, $6}' <<<"$line")"
                            printf '    %s [%s] <valor redactado>\n' "$head" "$class"
                        done
                        [[ "$class" == "credenciales" ]] && credenciales="$count" || pii=$((pii + count))
                    fi
                done
                printf '\n== ANÁLISIS ==\n'
                if (( code != 0 )); then
                    printf 'logcat no se pudo leer; la búsqueda de fugas no es concluyente\n'
                    verdict="ADVERTENCIA"
                elif (( credenciales > 0 )); then
                    printf 'HAY %s LÍNEA(S) CON POSIBLES CREDENCIALES O TOKENS EN LOS REGISTROS\n' "$credenciales"
                    verdict="CRÍTICO"
                elif (( pii > 0 )); then
                    printf 'hay %s línea(s) con posible PII (correo, RFC/CURP) en los registros\n' "$pii"
                    verdict="ADVERTENCIA"
                else
                    printf 'sin coincidencias de credenciales, tokens ni PII en los registros revisados\n'
                fi
            } >"$file"
            rm -f "$raw_log"
            ;;
        apps-terceros)
            local third_file debuggable_file
            third_file="$(mktemp --tmpdir audit-third.XXXXXX)"
            debuggable_file="$(mktemp --tmpdir audit-debuggable.XXXXXX)"
            {
                echo "== apps de terceros (pm list packages -3) =="
                if "${base[@]}" shell pm list packages -3 >"$third_file" 2>>"$file.err"; then
                    sed 's/^package://' "$third_file"
                    printf 'total de apps de terceros: %s\n' "$(wc -l <"$third_file" | tr -d ' ')"
                else
                    code=1
                    echo "pm list packages -3 falló; no se puede listar las apps de terceros"
                fi
                echo
                echo "== apps depurables (dumpsys package, flag DEBUGGABLE) =="
                # dumpsys package es una sola llamada; se cruza su salida
                # con la lista de terceros. El parseo agrupa por bloque
                # "Package [nombre]" y mira su línea flags=.
                if "${base[@]}" shell dumpsys package 2>>"$file.err" | awk '
                    /^Package \[/ { if (pkg != "" && flags ~ /DEBUGGABLE/) print pkg; pkg=$2; gsub(/\[|\]/, "", pkg); flags=""; next }
                    /^[[:space:]]*flags=/ { flags=$0 }
                    END { if (pkg != "" && flags ~ /DEBUGGABLE/) print pkg }
                ' | sort >"$debuggable_file"; then
                    if [[ -s "$debuggable_file" ]]; then
                        echo "apps depurables (todas, sistema y terceros):"
                        cat "$debuggable_file"
                    else
                        echo "sin apps depurables según dumpsys package"
                    fi
                else
                    code=1
                    echo "dumpsys package falló; no se puede determinar qué apps son depurables"
                fi
            } >"$file" 2>>"$file.err" || code=$?
            {
                printf '\n== ANÁLISIS ==\n'
                local third_count debuggable_third
                third_count="$(wc -l <"$third_file" | tr -d ' ')"
                debuggable_third="$(comm -12 <(sed 's/^package://' "$third_file" | sort) "$debuggable_file")"
                if [[ -n "$debuggable_third" ]]; then
                    printf 'APPS DE TERCEROS DEPURAABLES (%s de %s):\n%s\n' \
                        "$(printf '%s\n' "$debuggable_third" | wc -l | tr -d ' ')" "$third_count" "$debuggable_third"
                    printf 'una app depurable permite depurar su proceso y leer su memoria con adb; no la uses con datos reales\n'
                    verdict="CRÍTICO"
                elif (( code != 0 )); then
                    printf 'no se pudo determinar el estado depurable (pm o dumpsys fallaron)\n'
                    verdict="ADVERTENCIA"
                else
                    printf 'ninguna app de terceros depurable (%s apps de terceros revisadas)\n' "$third_count"
                fi
            } >>"$file"
            rm -f "$third_file" "$debuggable_file"
            ;;
    esac
    DONE_CHECKS+=("$check")
    DONE_FILES+=("$file")
    DONE_CODES+=("$code")
    DONE_DESCS+=("$(describe_check "$check")")
    DONE_VERDICTS+=("$verdict")
}

print_plan() {
    local seed check file
    seed="$(effective_seed)"
    printf 'PLAN DE AUDITORÍA ADB (dry-run, sin cambios)\n'
    printf 'Versión: %s | serial: %s | salida: %s | semilla: %s\n' "$AUDIT_VERSION" "${SERIAL:-<único dispositivo>}" "$OUT_DIR" "$seed"
    printf 'Clave del operador: %s\n' "${EXPECTED_KEY:-<~/.android/adbkey.pub si existe>}"
    printf 'Sonda de red al 5555: %s\n' "$([[ $NO_NETWORK_PROBE -eq 1 ]] && echo omitida || echo activa)"
    printf 'Orden aleatorio (semilla %s):\n' "$seed"
    mapfile -t _order < <(shuffled_checks "$seed")
    for check in "${_order[@]}"; do
        file="$(file_for_check "$check")"
        printf '+ %s> %s\n' "$(command_for_check "$check")" "$file"
    done
    printf 'Resumen: RESUMEN.txt (veredicto OK / ADVERTENCIA / CRÍTICO por comprobación)\n'
    printf 'Manifiesto: MANIFIESTO.txt (comando, código, bytes y SHA-256 por comprobación)\n'
}

print_plan_json() {
    local seed check file first=1
    seed="$(effective_seed)"
    printf '{\n'
    printf '  "version": "%s",\n' "$AUDIT_VERSION"
    printf '  "serial": "%s",\n' "$SERIAL"
    printf '  "out_dir": "%s",\n' "$OUT_DIR"
    printf '  "seed": "%s",\n' "$seed"
    printf '  "expected_key": "%s",\n' "$EXPECTED_KEY"
    printf '  "network_probe": %s,\n' "$([[ $NO_NETWORK_PROBE -eq 1 ]] && echo false || echo true)"
    printf '  "dry_run": %s,\n' "$([[ $DRY_RUN -eq 1 ]] && echo true || echo false)"
    printf '  "checks": ['
    mapfile -t _order < <(shuffled_checks "$seed")
    for check in "${_order[@]}"; do
        (( first )) && first=0 || printf ', '
        printf '"%s"' "$check"
    done
    printf '],\n  "files": [\n'
    first=1
    for check in "${_order[@]}"; do
        file="$(file_for_check "$check")"
        (( first )) && first=0 || printf ',\n'
        printf '    {"check": "%s", "description": "%s", "file": "%s", "command": "%s"}' \
            "$check" "$(describe_check "$check")" "$file" "$(command_for_check "$check" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/ *$//')"
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

audit() {
    check_device
    local seed
    seed="$(effective_seed)"
    RANDOM="$seed"
    umask 077
    local stamp safe_serial run_dir
    stamp="$(date -u +%Y%m%d-%H%M%S)"
    safe_serial="${SERIAL:-sin-serial}"
    safe_serial="${safe_serial//:/_}"
    run_dir="$OUT_DIR/AUDITORIA-${stamp}_${safe_serial}"
    mkdir -p "$run_dir"
    chmod 0700 "$run_dir"
    log "evidencia en $run_dir (0700; material sensible)"

    local check file first=1
    mapfile -t _order < <(shuffled_checks "$seed")
    for check in "${_order[@]}"; do
        (( first )) && first=0 || jitter
        file="$run_dir/$(file_for_check "$check")"
        run_check "$check" "$file"
    done

    local summary="$run_dir/RESUMEN.txt"
    {
        printf 'RESUMEN DE AUDITORÍA ADB\n'
        printf 'versión: %s\n' "$AUDIT_VERSION"
        printf 'fecha UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'serial: %s\n' "${SERIAL:-<único dispositivo>}"
        printf 'semilla de aleatorización: %s\n' "$seed"
        printf 'orden ejecutado: %s\n' "$(IFS=,; echo "${_order[*]}")"
        printf 'clave del operador: %s\n' "${EXPECTED_KEY:-<sin clave del operador para contrastar>}"
        printf '\n%-24s %-12s %s\n' "comprobación" "veredicto" "archivo"
        local i
        for i in "${!DONE_CHECKS[@]}"; do
            printf '%-24s %-12s %s\n' "${DONE_CHECKS[$i]}" "${DONE_VERDICTS[$i]}" "$(basename "${DONE_FILES[$i]}")"
        done
        printf '\nVeredictos: OK = sin hallazgos; ADVERTENCIA = revisa antes de conectar; CRÍTICO = no conectes sin resolverlo.\n'
        printf 'Un CRÍTICO en claves-rsa o en puerto-5555 significa que el dispositivo puede aceptar conexiones no autorizadas.\n'
    } >"$summary"
    chmod 0600 "$summary"

    local manifest="$run_dir/MANIFIESTO.txt"
    {
        printf 'MANIFIESTO DE AUDITORÍA ADB\n'
        printf 'versión: %s\n' "$AUDIT_VERSION"
        printf 'fecha UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'serial: %s\n' "${SERIAL:-<único dispositivo>}"
        printf 'semilla de aleatorización: %s\n' "$seed"
        printf 'directorio: %s\n' "$run_dir"
        printf '\n%-24s %-9s %-12s %10s  %s\n' "comprobación" "código" "veredicto" "bytes" "archivo (SHA-256)"
        local i bytes sha
        for i in "${!DONE_CHECKS[@]}"; do
            bytes="$(stat -c%s "${DONE_FILES[$i]}" 2>/dev/null || echo 0)"
            sha="$(sha256sum "${DONE_FILES[$i]}" 2>/dev/null | cut -d' ' -f1 || echo -)"
            printf '%-24s %-9s %-12s %10s  %s (%s)\n' "${DONE_CHECKS[$i]}" "${DONE_CODES[$i]}" "${DONE_VERDICTS[$i]}" "$bytes" \
                "$(basename "${DONE_FILES[$i]}")" "$sha"
            printf '  %s\n' "${DONE_DESCS[$i]}"
        done
        printf '\nRetención: material sensible; consérvalo solo según la autorización vigente.\n'
    } >"$manifest"
    chmod 0600 "$manifest"

    local criticals=0 warnings=0 v
    for v in "${DONE_VERDICTS[@]}"; do
        [[ "$v" == "CRÍTICO" ]] && criticals=$((criticals + 1))
        [[ "$v" == "ADVERTENCIA" ]] && warnings=$((warnings + 1))
    done
    log "auditoría completa en $run_dir"
    log "veredictos: $criticals CRÍTICO(S), $warnings ADVERTENCIA(S)"
    if (( criticals )); then
        log "CRÍTICO: no conectes el dispositivo sin resolver los hallazgos; revisa RESUMEN.txt"
    fi
    printf 'Resumen: %s\n' "$summary"
    printf 'Manifiesto: %s\n' "$manifest"
}

main() {
    while (($#)); do
        case "$1" in
            --serial) (($# >= 2)) || fail "--serial requiere SERIAL"; SERIAL="$2"; shift 2 ;;
            --out-dir) (($# >= 2)) || fail "--out-dir requiere PATH"; OUT_DIR="$2"; shift 2 ;;
            --checks) (($# >= 2)) || fail "--checks requiere LISTA"; CHECKS="$2"; shift 2 ;;
            --expected-key) (($# >= 2)) || fail "--expected-key requiere PATH"; EXPECTED_KEY="$2"; shift 2 ;;
            --seed) (($# >= 2)) || fail "--seed requiere N"; SEED="$2"; shift 2 ;;
            --sin-sonda-red) NO_NETWORK_PROBE=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            --plan-json) PLAN_JSON=1; shift ;;
            --confirm) CONFIRM=1; shift ;;
            -h|--help) usage; return 0 ;;
            *) fail "opción desconocida: $1" ;;
        esac
    done

    [[ -z "$CHECKS" ]] && CHECKS="$DEFAULT_CHECKS"
    if [[ -z "$EXPECTED_KEY" && -f "$HOME/.android/adbkey.pub" ]]; then
        EXPECTED_KEY="$HOME/.android/adbkey.pub"
    fi
    if [[ -n "$EXPECTED_KEY" ]]; then
        [[ -f "$EXPECTED_KEY" ]] || fail "la clave del operador no existe: $EXPECTED_KEY"
        validate_path "$EXPECTED_KEY"
    fi
    validate_serial
    validate_checks
    validate_seed
    validate_path "$OUT_DIR"
    if [[ "$OUT_DIR" != /* ]]; then OUT_DIR="$PWD/$OUT_DIR"; fi
    OUT_DIR="$(realpath -m -- "$OUT_DIR")"

    if (( PLAN_JSON )); then print_plan_json; return 0; fi
    if (( DRY_RUN )); then print_plan; return 0; fi
    (( CONFIRM )) || fail "auditoría real sin --confirm; usa --dry-run para revisar el plan y --confirm para auditar (dispositivo autorizado)"
    audit
}

main "$@"
