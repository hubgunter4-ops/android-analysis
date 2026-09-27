#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash -n src/no4nn.sh
bash -n src/android_toolchain/core.sh
python3 -m py_compile src/no4nn_gui.py
bash src/no4nn.sh --help | grep -q -- '--dry-run'
bash src/no4nn.sh --help | grep -q -- '--static-only'
bash src/no4nn.sh --help | grep -q -- '--plan-json'
bash src/no4nn.sh --help | grep -q -- '--gui'

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

test -s requirements.lock
grep -q '^setuptools==' requirements.lock
grep -q -- '--hash=sha256:' requirements.lock

printf '%s\n' 'test_installer.sh: OK'
