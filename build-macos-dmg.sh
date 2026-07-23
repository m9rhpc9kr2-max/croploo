#!/usr/bin/env bash
set -euo pipefail

# Build a release DMG for macOS.
# Must run on macOS.

cd "$(dirname "$0")"

APP_NAME="croploo"
VERSION=$(grep "^version:" pubspec.yaml | head -1 | awk '{print $2}' | cut -d'+' -f1)
DIST_DIR="dist"

mkdir -p "$DIST_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: macOS build must run on macOS." >&2
  exit 1
fi

echo "==> Building macOS release..."
flutter build macos --release

APP_BUNDLE="build/macos/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: ${APP_BUNDLE} not found." >&2
  exit 1
fi

DMG_PATH="${DIST_DIR}/${APP_NAME}-macos-${VERSION}.dmg"
rm -f "$DMG_PATH"

TMP_DIR=$(mktemp -d)
cp -R "$APP_BUNDLE" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"

echo "==> Creating DMG..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$TMP_DIR" \
  -format UDZO \
  -o "$DMG_PATH"

rm -rf "$TMP_DIR"
echo "==> Created ${DMG_PATH}"
