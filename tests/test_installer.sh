#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash -n src/no4nn.sh
bash -n src/android_toolchain/core.sh
bash -n src/android_toolchain/traces.sh
bash -n src/android_toolchain/audit.sh
python3 -m py_compile src/no4nn_gui.py src/ui/*.py
bash src/no4nn.sh --help | grep -q -- '--dry-run'
bash src/no4nn.sh --help | grep -q -- '--static-only'
bash src/no4nn.sh --help | grep -q -- '--plan-json'
bash src/no4nn.sh --help | grep -q -- '--gui'
bash src/no4nn.sh --help | grep -q -- '--traces'
bash src/no4nn.sh --help | grep -q -- '--audit'
bash src/android_toolchain/traces.sh --help | grep -q -- '--confirm'
bash src/android_toolchain/audit.sh --help | grep -q -- '--confirm'
bash src/android_toolchain/audit.sh --help | grep -q -- '--seed'

for style in 0 1 2; do
    output="$(bash src/no4nn.sh --dry-run --static-only --tools-dir "/tmp/tool09-$style" --banner-style "$style")"
    grep -q "banner=$style" <<<"$output"
    grep -Eiq 'ANDROID|APK|authorized|autorizad' <<<"$output"
done

static_output="$(bash src/no4nn.sh --dry-run --static-only --tools-dir /tmp/tool09-static)"
grep -q 'jadx' <<<"$static_output"
grep -q 'MobSF' <<<"$static_output"
grep -q -- '--requirement' <<<"$static_output"
grep -q 'requirements.lock' <<<"$static_output"
grep -q -- '--require-hashes' <<<"$static_output"
grep -q 'b5bda4fb4935ae8b3869b422454ae3b3896c7bc1' src/android_toolchain/core.sh
grep -q '7a4785fb3b55949231dd2b5d7df82ccba02a114f' src/android_toolchain/core.sh
! grep -q 'releases/latest' src/android_toolchain/core.sh

dynamic_output="$(bash src/no4nn.sh --dry-run --dynamic-only --tools-dir /tmp/tool09-dynamic)"
grep -q 'ADB' <<<"$dynamic_output"
grep -q 'frida\|mitmproxy' <<<"$dynamic_output"

if bash src/no4nn.sh --dry-run --static-only --dynamic-only >/dev/null 2>&1; then
    echo 'static-only y dynamic-only no fueron rechazados' >&2
    exit 1
fi

if bash src/no4nn.sh --dry-run --tools-dir $'bad\npath' >/dev/null 2>&1; then
    echo 'ruta con control no fue rechazada' >&2
    exit 1
fi

if bash src/no4nn.sh --dry-run --tools-dir ../escape >/dev/null 2>&1; then
    echo 'ruta con traversal no fue rechazada' >&2
    exit 1
fi

if bash src/no4nn.sh --dry-run --tools-dir foo/../../outside >/dev/null 2>&1; then
    echo 'traversal intermedio no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --dry-run --static-only --dynamic-only >/dev/null 2>&1; then
    echo 'modos incompatibles no fueron rechazados en la segunda comprobación' >&2
    exit 1
fi

if bash src/no4nn.sh --dry-run --static-only --plan-json --tools-dir /tmp/tool09-plan --banner-style 2 | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["static_enabled"] is True and d["dynamic_enabled"] is False and "static-analysis" in d["phases"]'; then
    :
else
    echo 'plan JSON inválido' >&2
    exit 1
fi

if bash src/no4nn.sh --dry-run --static-only --tools-dir /tmp/tool09 --banner-style 3 >/dev/null 2>&1; then
    echo 'banner inválido no fue rechazado' >&2
    exit 1
fi

if JADX_SHA256=not-a-checksum bash src/no4nn.sh --dry-run --static-only >/dev/null 2>&1; then
    echo 'checksum inválido no fue rechazado' >&2
    exit 1
fi

if JADX_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    bash src/no4nn.sh --dry-run --static-only >/dev/null 2>&1; then
    echo 'checksum no fijado no fue rechazado' >&2
    exit 1
fi

if grep -Eq '"(screencap|logcat|sqlite3|bugreport)"' src/no4nn_gui.py; then
    echo 'acción ADB sensible sigue exenta de confirmación' >&2
    exit 1
fi

# Apartado de trazas ADB: plan, validación y captura con adb falso.
traces_plan="$(bash src/no4nn.sh --traces --dry-run --serial emulator-5554)"
grep -q 'ps -A' <<<"$traces_plan"
grep -q 'logcat' <<<"$traces_plan"
grep -q 'dmesg' <<<"$traces_plan"
grep -q 'pstore' <<<"$traces_plan"
grep -q 'dropbox' <<<"$traces_plan"
! grep -q 'bugreport' <<<"$traces_plan"
grep -q 'bugreport' <<<"$(bash src/no4nn.sh --traces --dry-run --traces-sources bugreport)"
grep -q 'bugreport' <<<"$(bash src/android_toolchain/traces.sh --dry-run --include-bugreport)"

if bash src/no4nn.sh --traces --dry-run --traces-sources foo >/dev/null 2>&1; then
    echo 'fuente de trazas desconocida no fue rechazada' >&2
    exit 1
fi

if bash src/no4nn.sh --traces --dry-run --traces-serial 'bad;rm' >/dev/null 2>&1; then
    echo 'serial de trazas no válido no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --traces --dry-run --traces-dir ../escape >/dev/null 2>&1; then
    echo 'directorio de trazas con traversal no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --traces --serial emulator-5554 >/dev/null 2>&1; then
    echo 'captura de trazas sin --confirm no fue rechazada' >&2
    exit 1
fi

if bash src/no4nn.sh --traces --static-only --dry-run >/dev/null 2>&1; then
    echo '--traces combinado con --static-only no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --traces --plan-json --traces-sources procesos,kernel-dmesg | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["sources"] == ["procesos", "kernel-dmesg"] and len(d["files"]) == 2 and d["files"][0]["file"] == "01-procesos-ps-A.txt"'; then
    :
else
    echo 'plan JSON de trazas inválido' >&2
    exit 1
fi

grep -q 'askyesno' src/ui/traces_view.py
grep -q 'TracesView' src/no4nn_gui.py
grep -q 'TRAZAS ADB' src/no4nn_gui.py
grep -q 'docs/trazas-adb.md' README.md

# Apartado de auditoría ADB: plan, validación y auditoría con adb falso.
audit_plan="$(bash src/no4nn.sh --audit --dry-run --serial emulator-5554 --audit-seed 42)"
grep -q 'adb_keys' <<<"$audit_plan"
grep -q 'getprop' <<<"$audit_plan"
grep -q '5555' <<<"$audit_plan"
grep -q 'logcat' <<<"$audit_plan"
grep -q 'dumpsys package' <<<"$audit_plan"
grep -q 'semilla: 42' <<<"$audit_plan"
# La misma semilla da el mismo orden (aleatorización reproducible).
[[ "$(bash src/no4nn.sh --audit --dry-run --serial emulator-5554 --audit-seed 42 | grep -E '^\+' | md5sum)" \
   == "$(bash src/no4nn.sh --audit --dry-run --serial emulator-5554 --audit-seed 42 | grep -E '^\+' | md5sum)" ]]
grep -q 'sin-sonda-red' <<<"$(bash src/no4nn.sh --audit --dry-run --audit-sin-sonda-red)"

if bash src/no4nn.sh --audit --dry-run --audit-checks foo >/dev/null 2>&1; then
    echo 'comprobación de auditoría desconocida no fue rechazada' >&2
    exit 1
fi

if bash src/no4nn.sh --audit --dry-run --audit-serial 'bad;rm' >/dev/null 2>&1; then
    echo 'serial de auditoría no válido no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --audit --dry-run --audit-dir ../escape >/dev/null 2>&1; then
    echo 'directorio de auditoría con traversal no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --audit --dry-run --audit-seed abc >/dev/null 2>&1; then
    echo 'semilla no entera no fue rechazada' >&2
    exit 1
fi

if bash src/no4nn.sh --audit --serial emulator-5554 >/dev/null 2>&1; then
    echo 'auditoría sin --confirm no fue rechazada' >&2
    exit 1
fi

if bash src/no4nn.sh --audit --traces --dry-run >/dev/null 2>&1; then
    echo '--audit combinado con --traces no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --audit --static-only --dry-run >/dev/null 2>&1; then
    echo '--audit combinado con --static-only no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --audit --plan-json --audit-checks claves-rsa,puerto-5555 --audit-seed 7 | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["checks"] == ["puerto-5555", "claves-rsa"] and d["seed"] == "7" and d["network_probe"] is True and len(d["files"]) == 2'; then
    :
else
    echo 'plan JSON de auditoría inválido' >&2
    exit 1
fi

grep -q 'askyesno' src/ui/audit_view.py
grep -q 'AuditView' src/no4nn_gui.py
grep -q 'AUDITORÍA ADB' src/no4nn_gui.py
grep -q 'docs/auditoria-adb.md' README.md

# Apartado de conexión ADB y alcance de laboratorio.
bash -n src/android_toolchain/connect.sh
bash -n src/android_toolchain/scope.sh
bash src/no4nn.sh --help | grep -q -- '--connect'
bash src/no4nn.sh --help | grep -q -- '--scope-file'
bash src/android_toolchain/connect.sh --help | grep -q -- '--tcp'
bash src/android_toolchain/connect.sh --help | grep -q -- '--force'
bash src/android_toolchain/connect.sh --help | grep -q -- '--scope-file'

connect_plan="$(bash src/no4nn.sh --connect --dry-run --serial emulator-5554)"
grep -q 'adb version' <<<"$connect_plan"
grep -q 'adb devices -l' <<<"$connect_plan"
grep -q 'get-state' <<<"$connect_plan"
! grep -q 'kill-server' <<<"$connect_plan"
grep -q 'kill-server' <<<"$(bash src/no4nn.sh --connect --dry-run --connect-force)"
grep -q 'adb connect 192.168.1.42:5555' <<<"$(bash src/no4nn.sh --connect --dry-run --connect-tcp 192.168.1.42)"

if bash src/no4nn.sh --connect --dry-run --connect-tcp 999.1.1.1 >/dev/null 2>&1; then
    echo 'IP TCP no válida no fue rechazada' >&2
    exit 1
fi

if bash src/no4nn.sh --connect --dry-run --connect-timeout 0 >/dev/null 2>&1; then
    echo 'timeout no válido no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --connect --serial emulator-5554 --connect-force >/dev/null 2>&1; then
    echo 'forzar conexión sin --confirm no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --connect --traces --dry-run >/dev/null 2>&1; then
    echo '--connect combinado con --traces no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --connect --audit --dry-run >/dev/null 2>&1; then
    echo '--connect combinado con --audit no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --connect --static-only --dry-run >/dev/null 2>&1; then
    echo '--connect combinado con --static-only no fue rechazado' >&2
    exit 1
fi

if bash src/no4nn.sh --connect --plan-json --connect-force --connect-timeout 30 | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["force"] is True and d["timeout"] == 30 and "adb kill-server" in d["steps"]'; then
    :
else
    echo 'plan JSON de conexión inválido' >&2
    exit 1
fi

# Alcance: serial e IP fuera de alcance se rechazan; dentro, pasan.
scope_dir="$(mktemp -d)"
printf 'serial:emulator-5554\ntcp:192.168.1.0/24\n' >"$scope_dir/scope"
if bash src/no4nn.sh --connect --dry-run --serial emulator-9999 --scope-file "$scope_dir/scope" >/dev/null 2>&1; then
    echo 'serial fuera de alcance no fue rechazado' >&2
    exit 1
fi
if bash src/no4nn.sh --connect --dry-run --connect-tcp 10.0.0.5 --scope-file "$scope_dir/scope" >/dev/null 2>&1; then
    echo 'IP TCP fuera de alcance no fue rechazada' >&2
    exit 1
fi
bash src/no4nn.sh --connect --dry-run --serial emulator-5554 --scope-file "$scope_dir/scope" >/dev/null
bash src/no4nn.sh --connect --dry-run --connect-tcp 192.168.1.42 --scope-file "$scope_dir/scope" >/dev/null
if bash src/no4nn.sh --connect --dry-run --scope-file "$scope_dir/noexiste" >/dev/null 2>&1; then
    echo 'archivo de alcance explícito inexistente no fue rechazado' >&2
    exit 1
fi
if bash src/no4nn.sh --traces --dry-run --serial emulator-9999 --scope-file "$scope_dir/scope" >/dev/null 2>&1; then
    echo 'serial de trazas fuera de alcance no fue rechazado' >&2
    exit 1
fi
rm -rf "$scope_dir"

grep -q 'askyesno' src/ui/connect_view.py
grep -q 'ConnectView' src/no4nn_gui.py
grep -q 'CONEXIÓN ADB' src/no4nn_gui.py
grep -q 'docs/conexion-adb.md' README.md
grep -q 'docs/alcance-laboratorio.md' README.md
grep -q 'Detectar' src/ui/adb_view.py
grep -q 'Ejecutar módulo' src/ui/adb_view.py
grep -q 'Generar' src/ui/audit_view.py
grep -q 'device_detect' src/ui/audit_view.py src/ui/traces_view.py src/ui/connect_view.py src/ui/adb_view.py
grep -q 'wraplength' src/ui/theme.py

# Apartado de análisis de trazas (carpeta, archivos subidos y bugreport).
python3 -m py_compile src/android_toolchain/analyze_traces.py
bash src/no4nn.sh --help | grep -q -- '--analyze'
bash src/no4nn.sh --help | grep -q -- '--analyze-pedir-bugreport'
python3 src/android_toolchain/analyze_traces.py --help | grep -q -- '--max-muestras'

analyze_cap="$(mktemp -d)/20261115-101500_emulator-5554"
mkdir -p "$analyze_cap"
printf '%s\n' '11-15 10:15:00.123 12345 12345 E AndroidRuntime: FATAL EXCEPTION: main' \
    '11-15 10:15:00.124 12345 12345 E AndroidRuntime: java.lang.OutOfMemoryError: Failed to allocate' \
    >"$analyze_cap/03-logcat-errores.txt"
printf '%s\n' '11-15 10:15:00.000  1000  1000 E PowerManager: 2sec_reboot detected, power status Exception' \
    >"$analyze_cap/05-logcat-sistema.txt"
analyze_plan="$(bash src/no4nn.sh --analyze --dry-run --analyze-dir "$analyze_cap")"
grep -q 'PLAN DE ANÁLISIS DE TRAZAS' <<<"$analyze_plan"
grep -q '03-logcat-errores.txt' <<<"$analyze_plan"
analyze_out="$(mktemp -d)"
bash src/no4nn.sh --analyze --analyze-dir "$analyze_cap" --analyze-out-dir "$analyze_out" >/dev/null
analyze_run="$(ls -d "$analyze_out"/ANALISIS-*)"
test -f "$analyze_run/ANALISIS.txt"
test -f "$analyze_run/resumen.json"
test -f "$analyze_run/MANIFIESTO.txt"
python3 - "$analyze_run/resumen.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["por_clase"]["crash"] == 1, d["por_clase"]
assert d["por_clase"]["memoria"] == 1, d["por_clase"]
assert d["por_clase"]["reinicio-energia"] == 1, d["por_clase"]
assert d["total_lineas"] == 3, d
PY
if bash src/no4nn.sh --analyze --dry-run --analyze-dir /tmp/noexiste-analisis >/dev/null 2>&1; then
    echo 'carpeta de análisis inexistente no fue rechazada' >&2
    exit 1
fi
if bash src/no4nn.sh --analyze --connect --dry-run >/dev/null 2>&1; then
    echo '--analyze combinado con --connect no fue rechazado' >&2
    exit 1
fi
if bash src/no4nn.sh --analyze --analyze-pedir-bugreport --analyze-serial emulator-5554 >/dev/null 2>&1; then
    echo 'pedir bugreport sin --confirm no fue rechazado' >&2
    exit 1
fi
bash src/no4nn.sh --analyze --analyze-pedir-bugreport --analyze-serial emulator-5554 --dry-run | grep -q 'PLAN DE PETICIÓN DE BUGREPORT'
grep -q 'AnalyzeView' src/no4nn_gui.py
grep -q 'ANALIZAR TRAZAS' src/no4nn_gui.py
grep -q 'Subir archivo' src/ui/analyze_view.py
grep -q 'Solicitar bugreport' src/ui/analyze_view.py
grep -q 'docs/analizar-trazas.md' README.md
rm -rf "$(dirname "$analyze_cap")" "$analyze_out"

# Apartado de listado de apps (uso, conexiones, datos, acciones, PID).
bash -n src/android_toolchain/apps.sh
bash src/no4nn.sh --help | grep -q -- '--apps'
bash src/no4nn.sh --help | grep -q -- '--apps-todas'
bash src/android_toolchain/apps.sh --help | grep -q -- '--todas'
apps_plan="$(bash src/no4nn.sh --apps --dry-run --serial emulator-5554)"
grep -q 'PLAN DE APPS ADB' <<<"$apps_plan"
grep -q 'pm list packages' <<<"$apps_plan"
grep -q 'dumpsys netstats' <<<"$apps_plan"
grep -q 'ps -A' <<<"$apps_plan"
grep -q 'sistema: no' <<<"$apps_plan"
grep -q 'sistema: sí' <<<"$(bash src/no4nn.sh --apps --dry-run --apps-todas)"
if bash src/no4nn.sh --apps --plan-json --apps-todas | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["todas"] is True and len(d["sources"]) == 10'; then
    :
else
    echo 'plan JSON de apps inválido' >&2
    exit 1
fi
if bash src/no4nn.sh --apps --serial emulator-5554 >/dev/null 2>&1; then
    echo 'recogida de apps sin --confirm no fue rechazada' >&2
    exit 1
fi
if bash src/no4nn.sh --apps --traces --dry-run >/dev/null 2>&1; then
    echo '--apps combinado con --traces no fue rechazado' >&2
    exit 1
fi
grep -q 'AppsView' src/no4nn_gui.py
grep -q 'APPS' src/no4nn_gui.py
grep -q 'Detectar' src/ui/apps_view.py
grep -q 'docs/apps-uso-conexiones.md' README.md

# Auditoría real contra un adb falso (sin dispositivo).
audit_bin="$(mktemp -d)"
audit_out="$(mktemp -d)"
audit_home="$(mktemp -d)"
mkdir -p "$audit_home/.android"
printf '%s\n' 'AAAAB3operatorbase64key== operador@lab' >"$audit_home/.android/adbkey.pub"
cat >"$audit_bin/adb" <<'FAKEADB'
#!/usr/bin/env bash
args=("$@")
if [[ "${args[0]:-}" == "-s" ]]; then args=("${args[@]:2}"); fi
case "${args[*]}" in
  "devices") printf 'List of devices attached\nemulator-5554\tdevice\n' ;;
  "shell cat /data/misc/adb/adb_keys") printf 'AAAAB3operatorbase64key== operador@lab\nAAAAB3unknownbase64key== intruso@desconocido\n' ;;
  "shell getprop ro.debuggable") printf '0\n' ;;
  "shell getprop ro.secure") printf '1\n' ;;
  "shell getprop ro.adb.secure") printf '1\n' ;;
  "shell getprop service.adb.tcp.port") printf '\n' ;;
  "shell getprop persist.adb.tcp.port") printf '\n' ;;
  "shell getprop sys.usb.config") printf 'adb\n' ;;
  "shell getprop persist.sys.usb.config") printf 'adb\n' ;;
  "shell getprop ro.build.type") printf 'user\n' ;;
  "shell getprop ro.build.tags") printf 'release-keys\n' ;;
  "shell getprop ro.product.model") printf 'Redmi Note 13 Pro\n' ;;
  "shell getprop ro.build.version.release") printf '16\n' ;;
  "shell ip addr show") printf '2: wlan0: <BROADCAST,MULTICAST,UP> mtu 1500\n    inet 192.168.1.42/24 brd 192.168.1.255 scope global wlan0\n' ;;
  "shell ip route") printf 'default via 192.168.1.1 dev wlan0\n' ;;
  "shell ss -tlnp") printf 'State Recv-Q Send-Q Local Address:Port\nLISTEN 0 4096 0.0.0.0:5555 0.0.0.0:*\n' ;;
  "shell cat /proc/net/tcp") printf '  sl  local_address rem_address   st\n   0: 00000000:15B3 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 123 1 0000000000000000 100 0 0 10 0\n' ;;
  "shell cat /proc/net/tcp6") printf '  sl  local_address rem_address   st\n' ;;
  "shell ip -o -4 addr show") printf '2: wlan0    inet 192.168.1.42/24 brd 192.168.1.255 scope global wlan0\n' ;;
  "logcat -d -v threadtime -b main -b system -b events -b crash") printf '01-01 00:00:01.000  1000  1000 I TestTag: Authorization: Bearer abc123faketoken\n01-01 00:00:02.000  1000  1000 D OtherTag: usuario contacto@example.com inicio sesion\n01-01 00:00:03.000  1000  1000 I TestTag: operacion normal sin secretos\n' ;;
  "shell pm list packages -3") printf 'package:com.example.app1\npackage:com.example.app2\npackage:com.example.app3\n' ;;
  "shell dumpsys package") printf 'Package [com.example.app1] (1234567):\n  codePath=/data/app/com.example.app1-1/base.apk\n  flags=[ DEBUGGABLE HAS_CODE ALLOW_CLEAR_USER_DATA ]\nPackage [com.example.app2] (1234568):\n  codePath=/data/app/com.example.app2-1/base.apk\n  flags=[ HAS_CODE ALLOW_CLEAR_USER_DATA ]\nPackage [com.android.systemui] (1234569):\n  codePath=/system/priv-app/SystemUI/SystemUI.apk\n  flags=[ SYSTEM HAS_CODE ]\n' ;;
  *) echo "fake adb: comando no esperado: ${args[*]}" >&2; exit 3 ;;
esac
FAKEADB
chmod +x "$audit_bin/adb"
HOME="$audit_home" PATH="$audit_bin:$PATH" bash src/android_toolchain/audit.sh --serial emulator-5554 --confirm --seed 42 --sin-sonda-red --out-dir "$audit_out" >"$audit_out.log" 2>&1
audit_dir="$(find "$audit_out" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
test -n "$audit_dir"
for f in 01-claves-rsa-autorizadas.txt 02-propiedades-depuracion.txt 03-exposicion-red.txt 04-puerto-5555.txt 05-fuga-datos-sensibles.txt 06-apps-terceros-depurables.txt RESUMEN.txt MANIFIESTO.txt; do test -s "$audit_dir/$f"; done
grep -q 'DESCONOCIDA' "$audit_dir/01-claves-rsa-autorizadas.txt"
grep -q 'total de claves autorizadas: 2' "$audit_dir/01-claves-rsa-autorizadas.txt"
grep -q 'ro.debuggable=0' "$audit_dir/02-propiedades-depuracion.txt"
grep -q '192.168.1.42' "$audit_dir/03-exposicion-red.txt"
grep -q '00000000:15B3' "$audit_dir/04-puerto-5555.txt"
grep -q 'sonda de red omitida' "$audit_dir/04-puerto-5555.txt"
grep -q 'credenciales.*2 coincidencia' "$audit_dir/05-fuga-datos-sensibles.txt"
! grep -q 'abc123faketoken' "$audit_dir/05-fuga-datos-sensibles.txt"
! grep -q 'contacto@example.com' "$audit_dir/05-fuga-datos-sensibles.txt"
grep -q 'valor redactado' "$audit_dir/05-fuga-datos-sensibles.txt"
grep -q 'com.example.app1' "$audit_dir/06-apps-terceros-depurables.txt"
grep -q 'total de apps de terceros: 3' "$audit_dir/06-apps-terceros-depurables.txt"
grep -Eq '^claves-rsa +CRÍTICO' "$audit_dir/RESUMEN.txt"
grep -Eq '^propiedades-depuracion +OK' "$audit_dir/RESUMEN.txt"
grep -Eq '^exposicion-red +ADVERTENCIA' "$audit_dir/RESUMEN.txt"
grep -Eq '^puerto-5555 +CRÍTICO' "$audit_dir/RESUMEN.txt"
grep -Eq '^fuga-datos +CRÍTICO' "$audit_dir/RESUMEN.txt"
grep -Eq '^apps-terceros +CRÍTICO' "$audit_dir/RESUMEN.txt"
grep -q 'semilla de aleatorización: 42' "$audit_dir/RESUMEN.txt"
test "$(stat -c %a "$audit_dir")" = 700
rm -rf "$audit_bin" "$audit_out" "$audit_home" "$audit_out.log"

# Captura real contra un adb falso (sin dispositivo).
fake_bin="$(mktemp -d)"
fake_out="$(mktemp -d)"
cat >"$fake_bin/adb" <<'FAKEADB'
#!/usr/bin/env bash
args=("$@")
if [[ "${args[0]:-}" == "-s" ]]; then args=("${args[@]:2}"); fi
case "${args[*]}" in
  "devices") printf 'List of devices attached\nemulator-5554\tdevice\n' ;;
  "shell ps -A") printf 'USER PID PPID NAME\nroot 1 0 init\n' ;;
  "shell top -n 1 -b") printf 'Tasks: 1 total\n  PID USER ARGS\n    1 root init\n' ;;
  "logcat -d -v threadtime *:E") printf '01-01 00:00:01.000 1000 1000 E TestTag: error de prueba\n' ;;
  "logcat -d -b crash -v threadtime") printf '01-01 00:00:02.000 1000 1000 F TestTag: crash de prueba\n' ;;
  "logcat -d -b system -b main -b events -v threadtime *:W") printf '01-01 00:00:03.000 1000 1000 W TestTag: aviso de prueba\n' ;;
  "shell dmesg -T") echo "dmesg: Operation not permitted" >&2; exit 1 ;;
  "shell dmesg") printf '[    0.000000] Linux version fake (test)\n' ;;
  "shell ls -l /sys/fs/pstore") printf 'total 0\n' ;;
  "shell cat /sys/fs/pstore/*") echo "sin archivos en pstore" >&2; exit 1 ;;
  "shell cat /proc/last_kmsg") echo "last_kmsg no disponible" >&2; exit 1 ;;
  "shell dumpsys dropbox --print") printf '2026-01-01 00:00:00 data_app_anr (test)\n' ;;
  *) echo "fake adb: comando no esperado: ${args[*]}" >&2; exit 3 ;;
esac
FAKEADB
chmod +x "$fake_bin/adb"
PATH="$fake_bin:$PATH" bash src/android_toolchain/traces.sh --serial emulator-5554 --confirm --out-dir "$fake_out" >"$fake_out.log" 2>&1
run_dir="$(find "$fake_out" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
test -n "$run_dir"
for f in 01-procesos-ps-A.txt 02-procesos-top.txt 03-logcat-errores.txt 04-logcat-crash.txt 05-logcat-sistema.txt 06-kernel-dmesg.txt 07-kernel-anterior-pstore.txt 08-fallos-dropbox.txt MANIFIESTO.txt; do test -s "$run_dir/$f"; done
grep -q 'Linux version fake' "$run_dir/06-kernel-dmesg.txt"
grep -Eq '^kernel-dmesg +0 +[0-9]+' "$run_dir/MANIFIESTO.txt"
grep -q 'SHA-256' "$run_dir/MANIFIESTO.txt"
test "$(stat -c %a "$run_dir")" = 700
test ! -e "$run_dir/09-bugreport.zip"
rm -rf "$fake_bin" "$fake_out" "$fake_out.log"

test -s requirements.lock
grep -q '^setuptools==' requirements.lock
grep -q -- '--hash=sha256:' requirements.lock

printf '%s\n' 'test_installer.sh: OK'
