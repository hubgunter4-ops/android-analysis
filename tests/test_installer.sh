#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash -n src/no4nn.sh
bash -n src/android_toolchain/core.sh
bash -n src/android_toolchain/traces.sh
python3 -m py_compile src/no4nn_gui.py src/ui/*.py
bash src/no4nn.sh --help | grep -q -- '--dry-run'
bash src/no4nn.sh --help | grep -q -- '--static-only'
bash src/no4nn.sh --help | grep -q -- '--plan-json'
bash src/no4nn.sh --help | grep -q -- '--gui'
bash src/no4nn.sh --help | grep -q -- '--traces'
bash src/android_toolchain/traces.sh --help | grep -q -- '--confirm'

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
