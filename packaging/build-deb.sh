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
cp -r "$ROOT_DIR/src" "$ROOT_DIR/docs" "$ROOT_DIR/install.sh" "$ROOT_DIR/requirements.txt" "$ROOT_DIR/requirements.in" "$ROOT_DIR/requirements.lock" "$STAGE_DIR/usr/share/android-analysis/"
find "$STAGE_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} +
# dpkg-deb rechaza directorios con permisos de grupo de escritura/setgid
# (p. ej. clones con 2770); normaliza los directorios a 0755.
find "$STAGE_DIR" -type d -exec chmod 0755 {} +
find "$STAGE_DIR/usr/share/android-analysis" -type f -exec chmod 0644 {} +
# lintian exige el changelog comprimido como changelog.Debian.gz.
gzip -9 -n -c "$STAGE_DIR/usr/share/doc/android-analysis-toolchain/changelog" \
    > "$STAGE_DIR/usr/share/doc/android-analysis-toolchain/changelog.Debian.gz"
rm -f "$STAGE_DIR/usr/share/doc/android-analysis-toolchain/changelog"
chmod 755 \
    "$STAGE_DIR/usr/bin/android-analysis" \
    "$STAGE_DIR/DEBIAN/postinst" \
    "$STAGE_DIR/usr/share/android-analysis/src/no4nn.sh" \
    "$STAGE_DIR/usr/share/android-analysis/src/android_toolchain/traces.sh" \
    "$STAGE_DIR/usr/share/android-analysis/src/android_toolchain/audit.sh" \
    "$STAGE_DIR/usr/share/android-analysis/src/android_toolchain/connect.sh" \
    "$STAGE_DIR/usr/share/android-analysis/src/no4nn_gui.py" \
    "$STAGE_DIR/usr/share/android-analysis/install.sh"

dpkg-deb --build --root-owner-group "$STAGE_DIR" "$OUTPUT"
printf 'Paquete creado: %s\n' "$OUTPUT"
