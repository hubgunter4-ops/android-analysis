#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_DIR="$ROOT_DIR/packaging/debian"
VERSION="${1:-2.1.0}"
OUTPUT="$ROOT_DIR/android-analysis-toolchain_${VERSION}_all.deb"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp -a "$TEMPLATE_DIR/." "$STAGE_DIR/"
mkdir -p "$STAGE_DIR/usr/share/android-analysis"
cp -r "$ROOT_DIR/src" "$ROOT_DIR/docs" "$ROOT_DIR/install.sh" "$STAGE_DIR/usr/share/android-analysis/"
find "$STAGE_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} +
chmod 755 \
    "$STAGE_DIR/usr/bin/android-analysis" \
    "$STAGE_DIR/DEBIAN/postinst" \
    "$STAGE_DIR/usr/share/android-analysis/src/no4nn.sh" \
    "$STAGE_DIR/usr/share/android-analysis/src/no4nn_gui.py" \
    "$STAGE_DIR/usr/share/android-analysis/install.sh"

dpkg-deb --build "$STAGE_DIR" "$OUTPUT"
printf 'Paquete creado: %s\n' "$OUTPUT"
