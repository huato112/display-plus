#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: ./scripts/release.sh v1.0.0}"

echo "=== Building Release ${VERSION} ==="

# Build and package DMG
./scripts/build-dmg.sh

# Create GitHub Release
echo "=== Creating GitHub Release ==="
gh release create "$VERSION" \
  --title "DisplayPlus ${VERSION}" \
  --notes-file CHANGELOG.md \
  DisplayPlus.dmg

echo "=== Release ${VERSION} published ==="
