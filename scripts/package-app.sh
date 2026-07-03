#!/usr/bin/env bash
# Build the SwiftPM executable and wrap it into a double-clickable "Folio.app"
# with the right bundle identifier. Run from the repo root: make app
set -euo pipefail

APP_NAME="Folio"
BUNDLE_ID="com.sriramb.folio"
VERSION="0.1.0"
CONFIG="${1:-release}"

if [[ ! -f Package.swift ]]; then
    echo "error: run this from the folio repo root (try: make app)" >&2
    exit 1
fi

echo "› swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Folio"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Folio"
cp "Resources/AppIcon/Folio.icns" "$APP/Contents/Resources/Folio.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>Folio</string>
    <key>CFBundleIconFile</key><string>Folio.icns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSMultipleInstancesProhibited</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper lets it run locally.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
    echo "  (codesign skipped — app will still run locally)"

echo "✓ Built $APP"
