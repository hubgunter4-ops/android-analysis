#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if (($# == 0)); then set -- --help; fi
exec "$ROOT_DIR/src/no4nn.sh" "$@"
