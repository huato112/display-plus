#!/bin/bash
# Build, install and launch DisplayPlus with one command.
# Usage: ./build.sh [--dmg] [--no-launch]

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/DisplayPlus.app"
INSTALL_PATH="/Applications/DisplayPlus.app"
BUILD_LOG="$BUILD_DIR/build.log"
CREATE_DMG=false
LAUNCH_APP=true
NEED_SUDO=false
INSTALL_STAGING=""

for argument in "$@"; do
    case "$argument" in
        --dmg) CREATE_DMG=true ;;
        --no-launch) LAUNCH_APP=false ;;
        -h|--help)
            echo "Usage: $0 [--dmg] [--no-launch]"
            echo "Build Release, install to /Applications, and launch DisplayPlus."
            echo "  --dmg        Also create build/DisplayPlus.dmg"
            echo "  --no-launch  Install without launching the app"
            exit 0
            ;;
        *) echo "Unknown option: $argument" >&2; exit 1 ;;
    esac
done

if [ "$(uname -s)" != Darwin ]; then
    echo "ERROR: DisplayPlus requires macOS and Xcode." >&2
    exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "ERROR: Install Xcode and select it with:" >&2
    echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "ERROR: Install XcodeGen first: brew install xcodegen" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR"
cd "$PROJECT_ROOT"

echo "==> Generating Xcode project…"
xcodegen generate --spec "$PROJECT_ROOT/project.yml" --project "$PROJECT_ROOT"

echo "==> Building Release (log: $BUILD_LOG)…"
if ! xcodebuild \
    -project "$PROJECT_ROOT/DisplayPlus.xcodeproj" \
    -scheme DisplayPlus \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    build >"$BUILD_LOG" 2>&1; then
    tail -n 80 "$BUILD_LOG" >&2
    echo "ERROR: Build failed. Full log: $BUILD_LOG" >&2
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Build did not produce $APP_PATH" >&2
    exit 1
fi

echo "==> Signing local app…"
xattr -cr "$APP_PATH"
codesign --force --sign - \
    --entitlements "$PROJECT_ROOT/DisplayPlus/DisplayPlus.entitlements" \
    --options runtime "$APP_PATH"
codesign --verify --strict "$APP_PATH"

if "$CREATE_DMG"; then
    echo "==> Creating DMG…"
    DMG_STAGING="$BUILD_DIR/dmg-staging"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    ditto "$APP_PATH" "$DMG_STAGING/DisplayPlus.app"
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create -volname DisplayPlus -srcfolder "$DMG_STAGING" \
        -ov -format UDZO "$BUILD_DIR/DisplayPlus.dmg"
fi

install_command() {
    if "$NEED_SUDO"; then
        sudo "$@"
    else
        "$@"
    fi
}

# Stage the complete bundle before stopping or replacing the installed app.
if [ ! -w /Applications ] || { [ -e "$INSTALL_PATH" ] && [ ! -w "$INSTALL_PATH" ]; }; then
    NEED_SUDO=true
    echo "==> Administrator access is needed to install in /Applications…"
    sudo -v
fi

cleanup() {
    if [ -n "$INSTALL_STAGING" ]; then
        # Restore the previous bundle if the final move failed.
        if [ ! -e "$INSTALL_PATH" ] && [ -e "$INSTALL_STAGING/previous.app" ]; then
            install_command mv "$INSTALL_STAGING/previous.app" "$INSTALL_PATH" || return
        fi
        install_command rm -rf "$INSTALL_STAGING"
    fi
}
trap cleanup EXIT

echo "==> Installing to /Applications…"
INSTALL_STAGING="$(install_command mktemp -d /Applications/.DisplayPlus-install.XXXXXX)"
install_command ditto "$APP_PATH" "$INSTALL_STAGING/DisplayPlus.app"
install_command codesign --verify --strict "$INSTALL_STAGING/DisplayPlus.app"

if pgrep -x DisplayPlus >/dev/null 2>&1; then
    osascript -e 'quit app "DisplayPlus"' 2>/dev/null || true
    killall DisplayPlus 2>/dev/null || true
fi
if [ -e "$INSTALL_PATH" ]; then
    install_command mv "$INSTALL_PATH" "$INSTALL_STAGING/previous.app"
fi
install_command mv "$INSTALL_STAGING/DisplayPlus.app" "$INSTALL_PATH"

if "$LAUNCH_APP"; then
    echo "==> Launching DisplayPlus…"
    open "$INSTALL_PATH"
fi

echo "Done! Installed: $INSTALL_PATH"
if "$CREATE_DMG"; then
    echo "DMG: $BUILD_DIR/DisplayPlus.dmg"
fi
