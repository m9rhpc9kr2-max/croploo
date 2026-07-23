#!/usr/bin/env bash
set -euo pipefail

# Build a release .tar.gz (and AppImage) containing the Linux bundle.
# On a Linux host this builds locally. On macOS/Windows it automatically
# triggers just the Linux build on GitHub Actions instead (requires gh CLI).

cd "$(dirname "$0")"

APP_NAME="croploo"
VERSION=$(grep "^version:" pubspec.yaml | head -1 | awk '{print $2}' | cut -d'+' -f1)
DIST_DIR="dist"

if [[ "$(uname -s)" != "Linux" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: Linux build must run on Linux." >&2
    echo "On macOS/Windows, this script needs the GitHub CLI (gh) to trigger a remote build." >&2
    echo "Install it from https://cli.github.com/" >&2
    exit 1
  fi

  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
  echo "==> Not on Linux: triggering remote Linux build on GitHub Actions..."
  gh workflow run build-desktop.yml --ref "$CURRENT_BRANCH" -f platform=linux
  echo "==> Build triggered. Download the artifact from GitHub Actions when it completes."
  exit 0
fi

mkdir -p "$DIST_DIR"

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
