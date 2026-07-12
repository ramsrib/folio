#!/usr/bin/env bash
# Build the SwiftPM executable and wrap it into a double-clickable "Folio.app"
# with the right bundle identifier. Run from the repo root: make app
set -euo pipefail

APP_NAME="Folio"
BUNDLE_ID="com.sriramb.folio"
# scripts/release.sh passes the version being released; it then asserts the
# built Info.plist matches, so this default only applies to local builds.
VERSION="${MARKETING_VERSION:-0.1.0}"
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

# Sign. A Developer ID signature is what lets someone who *downloads* the app
# open it without Gatekeeper stopping them, so prefer it and fall back to ad-hoc
# (fine locally, not for a release — scripts/release.sh warns when it happens).
if [[ -z "${CODE_SIGN_IDENTITY:-}" ]]; then
    for KIND in "Developer ID Application" "Apple Development"; do
        LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep "\"$KIND" | head -1 || true)"
        if [[ -n "$LINE" ]]; then
            CODE_SIGN_IDENTITY="$(echo "$LINE" | awk '{print $2}')"
            echo "› signing with $KIND ($CODE_SIGN_IDENTITY)"
            break
        fi
    done
fi
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
[[ "$CODE_SIGN_IDENTITY" == "-" ]] && echo "› no signing identity found; signing ad-hoc"

# --options runtime (hardened runtime) is required for notarization; harmless
# when signing ad-hoc locally.
codesign --force --deep --options runtime --timestamp \
    --sign "$CODE_SIGN_IDENTITY" "$APP" >/dev/null 2>&1 || \
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
    echo "  (codesign skipped — app will still run locally)"

echo "✓ Built $APP ($VERSION)"
