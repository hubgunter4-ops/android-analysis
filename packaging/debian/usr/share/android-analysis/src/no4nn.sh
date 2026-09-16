#!/usr/bin/env bash
# no4nn.sh — Android analysis toolchain installer
# Entry point estable; uso ofensivo exclusivamente autorizado.

set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == "--gui" ]]; then
    shift
    if (($#)); then
        printf 'Error: --gui no acepta opciones adicionales; configúralas en la interfaz.\n' >&2
        exit 2
    fi
    exec python3 "$ROOT_DIR/src/no4nn_gui.py"
fi

# shellcheck source=src/android_toolchain/core.sh
source "$ROOT_DIR/src/android_toolchain/core.sh"
android_toolchain_main "$@"
