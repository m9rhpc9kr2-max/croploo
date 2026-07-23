#!/usr/bin/env bash
set -euo pipefail

# Build a release .zip containing the Windows .exe and its data folder.
# On a Windows host this builds locally. On macOS/Linux it automatically
# triggers the GitHub Actions Windows build instead (requires gh CLI).

cd "$(dirname "$0")"

APP_NAME="croploo"
VERSION=$(grep "^version:" pubspec.yaml | head -1 | awk '{print $2}' | cut -d'+' -f1)
DIST_DIR="dist"

for arg in "$@"; do
  case "$arg" in
    --remote) ;; # kept for backwards compatibility; remote build is now automatic
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Flutter's Windows target can only be built on Windows.
if [[ "$(uname -s)" != "Windows_NT" ]] && [[ "$(uname -s)" != "MINGW"* ]] && [[ "$(uname -s)" != "CYGWIN"* ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: Windows release must be built on a Windows host." >&2
    echo "On macOS/Linux, this script needs the GitHub CLI (gh) to trigger a remote build." >&2
    echo "Install it from https://cli.github.com/" >&2
    exit 1
  fi

  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
  echo "==> Not on Windows: triggering remote Windows build on GitHub Actions..."
  gh workflow run build-desktop.yml --ref "$CURRENT_BRANCH"
  echo "==> Build triggered. Download the artifact from GitHub Actions when it completes."
  exit 0
fi

mkdir -p "$DIST_DIR"

echo "==> Building Windows release..."
flutter build windows --release

RELEASE_DIR="build/windows/x64/runner/Release"
if [[ ! -d "$RELEASE_DIR" ]]; then
  RELEASE_DIR="build/windows/runner/Release"
fi
if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "Error: Windows release directory not found." >&2
  exit 1
fi

EXE_PATH="${RELEASE_DIR}/${APP_NAME}.exe"
if [[ ! -f "$EXE_PATH" ]]; then
  echo "Error: ${EXE_PATH} not found." >&2
  exit 1
fi

find_iscc() {
  if command -v iscc >/dev/null 2>&1; then
    command -v iscc
    return
  fi
  for candidate in \
    "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
    "/c/Program Files/Inno Setup 6/ISCC.exe"
  do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done
}

ISCC_BIN=$(find_iscc || true)
if [[ -n "$ISCC_BIN" ]]; then
  echo "==> Building Windows installer with Inno Setup..."
  # MSYS_NO_PATHCONV avoids Git Bash mangling "/DAppVersion=..." into a
  # drive-letter path (e.g. "D:AppVersion=...") before ISCC sees it.
  MSYS_NO_PATHCONV=1 "$ISCC_BIN" "/DAppVersion=$VERSION" windows/installer.iss
  echo "==> Created ${DIST_DIR}/${APP_NAME}-windows-setup.exe"
else
  echo "Warning: Inno Setup (iscc) not found, skipping installer .exe (only the zip will be created)." >&2
fi

ZIP_NAME="${APP_NAME}-windows-${VERSION}.zip"
ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"
rm -f "$ZIP_PATH"

echo "==> Packaging release folder into ${ZIP_NAME}..."
if command -v zip >/dev/null 2>&1; then
  (cd "$RELEASE_DIR" && zip -r -q "$OLDPWD/$ZIP_PATH" .)
else
  # Fallback: tar.gz (tar is available on Windows 10+ and Git Bash)
  TAR_NAME="${APP_NAME}-windows-${VERSION}.tar.gz"
  TAR_PATH="${DIST_DIR}/${TAR_NAME}"
  rm -f "$TAR_PATH"
  tar -czf "$TAR_PATH" -C "$RELEASE_DIR" .
  echo "==> Created ${TAR_PATH} (zip was not available)"
  exit 0
fi

echo "==> Created ${ZIP_PATH}"
echo "    Executable: ${EXE_PATH}"
