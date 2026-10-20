#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/forma-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Forma.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Forma" "$app/Contents/MacOS/Forma"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"; fi
xattr -cr "$app"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$app" dist/Forma-macOS.zip
ditto "$app" dist/Forma.app
echo "Built dist/Forma.app and dist/Forma-macOS.zip"
