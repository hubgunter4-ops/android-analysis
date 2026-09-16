#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT_DIR/packaging/debian"
VERSION="${1:-2.1.0}"
OUTPUT="$ROOT_DIR/android-analysis-toolchain_${VERSION}_all.deb"

rm -rf "$PKG_DIR/usr/share/android-analysis"
mkdir -p "$PKG_DIR/usr/share/android-analysis"
cp -r "$ROOT_DIR/src" "$ROOT_DIR/docs" "$ROOT_DIR/install.sh" "$PKG_DIR/usr/share/android-analysis/"
chmod 755 \
    "$PKG_DIR/usr/bin/android-analysis" \
    "$PKG_DIR/DEBIAN/postinst" \
    "$PKG_DIR/usr/share/android-analysis/src/no4nn.sh" \
    "$PKG_DIR/usr/share/android-analysis/src/no4nn_gui.py" \
    "$PKG_DIR/usr/share/android-analysis/install.sh"

dpkg-deb --build "$PKG_DIR" "$OUTPUT"
printf 'Paquete creado: %s\n' "$OUTPUT"
