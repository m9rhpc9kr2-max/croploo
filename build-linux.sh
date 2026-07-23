#!/usr/bin/env bash
set -euo pipefail

# Build a release .tar.gz containing the Linux bundle.
# Must run on Linux.

cd "$(dirname "$0")"

APP_NAME="croploo"
VERSION=$(grep "^version:" pubspec.yaml | head -1 | awk '{print $2}' | cut -d'+' -f1)
DIST_DIR="dist"

mkdir -p "$DIST_DIR"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Error: Linux build must run on Linux." >&2
  exit 1
fi

echo "==> Building Linux release..."
flutter build linux --release

BUNDLE_DIR="build/linux/x64/release/bundle"
if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Error: ${BUNDLE_DIR} not found." >&2
  exit 1
fi

TAR_NAME="${APP_NAME}-linux-${VERSION}.tar.gz"
TAR_PATH="${DIST_DIR}/${TAR_NAME}"
rm -f "$TAR_PATH"

echo "==> Packaging bundle into ${TAR_NAME}..."
tar -czf "$TAR_PATH" -C "$BUNDLE_DIR" .

echo "==> Created ${TAR_PATH}"
echo "    Executable: ${BUNDLE_DIR}/${APP_NAME}"

# Package an AppImage too, if appimagetool is available.
APPIMAGETOOL="$(command -v appimagetool || true)"
if [[ -n "$APPIMAGETOOL" ]]; then
  echo "==> Building AppImage..."

  APPDIR=$(mktemp -d)
  mkdir -p "${APPDIR}/usr/bin"
  cp -R "${BUNDLE_DIR}/." "${APPDIR}/usr/bin/"
  cp linux/packaging/croploo.png "${APPDIR}/croploo.png"

  {
    echo '#!/bin/sh'
    echo 'HERE="$(dirname "$(readlink -f "$0")")"'
    echo "exec \"\${HERE}/usr/bin/${APP_NAME}\" \"\$@\""
  } > "${APPDIR}/AppRun"
  chmod +x "${APPDIR}/AppRun"

  cat > "${APPDIR}/${APP_NAME}.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Croploo
Exec=${APP_NAME}
Icon=croploo
Categories=Office;Finance;
DESKTOP

  APPIMAGE_NAME="${APP_NAME}-linux.AppImage"
  APPIMAGE_PATH="${DIST_DIR}/${APPIMAGE_NAME}"
  rm -f "$APPIMAGE_PATH"

  ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run "$APPDIR" "$APPIMAGE_PATH"
  rm -rf "$APPDIR"

  echo "==> Created ${APPIMAGE_PATH}"
else
  echo "Warning: appimagetool not found, skipping AppImage (only the tar.gz was created)." >&2
fi
