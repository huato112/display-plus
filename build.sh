#!/bin/bash
# DisplayPlus — Build & Package Script
# Usage:  ./build.sh
# Output: build/DisplayPlus.dmg

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/DisplayPlus.xcarchive"
APP_EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$APP_EXPORT_DIR/DisplayPlus.app"
DMG_PATH="$BUILD_DIR/DisplayPlus.dmg"
INSTALL_PATH="/Applications/DisplayPlus.app"

echo "==> Cleaning build dir…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving (Release)…"
# Note: grep is filtered for readability; `|| true` keeps a no-match (BSD grep exit 1) from
# aborting under `set -e`. Real failures are caught by the artifact checks below.
xcodebuild \
    -scheme DisplayPlus \
    -configuration Release \
    archive \
    -archivePath "$ARCHIVE_PATH" \
    | grep -E "error:|warning:|Build succeeded|ARCHIVE SUCCEEDED" || true

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "ERROR: archive failed — $ARCHIVE_PATH was not produced" >&2
    exit 1
fi

echo "==> Exporting .app…"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$APP_EXPORT_DIR" \
    -exportOptionsPlist "$PROJECT_ROOT/ExportOptions.plist" \
    | grep -E "error:|EXPORT SUCCEEDED" || true

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: export failed — $APP_PATH was not produced" >&2
    exit 1
fi

echo "==> Creating DMG…"
hdiutil create \
    -volname "DisplayPlus" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "==> Installing to /Applications…"
# Quit any running instance so we can replace the bundle, then relaunch the
# fresh build. A locally-built app has no quarantine attribute, so /Applications
# launches it without the right-click → Open Gatekeeper dance.
osascript -e 'quit app "DisplayPlus"' 2>/dev/null || true
killall DisplayPlus 2>/dev/null || true
rm -rf "$INSTALL_PATH"
cp -R "$APP_PATH" "$INSTALL_PATH"
open "$INSTALL_PATH"

echo ""
echo "Done! Output:"
echo "  Installed: $INSTALL_PATH (launched)"
echo "  App:       $APP_PATH"
echo "  DMG:       $DMG_PATH"
echo ""
echo "Note: The DMG is unsigned — anyone installing from it must right-click → Open"
echo "      the first time. The /Applications copy above was built locally, so it"
echo "      has no quarantine flag and opens normally."
