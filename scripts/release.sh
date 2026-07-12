#!/usr/bin/env bash
#
# release.sh — build, sign, notarize, package, and publish a release to GitHub.
#
#   make release VERSION=v0.1.0
#
# Steps:
#   1. Preflight: version is well-formed, unused, and follows the last tag; the
#      working tree is clean and pushed (a tag must name code others can get).
#   2. Clean release build of the .app, Developer ID–signed (scripts/package-app.sh).
#   3. Notarize + staple when credentials are available (.env). Skipped otherwise —
#      the artifacts still work, but downloaders hit Gatekeeper and must approve
#      the app by hand in System Settings → Privacy & Security.
#   4. Package: a .zip (ditto) and a .dmg (create-dmg, else hdiutil).
#   5. Tag and publish the GitHub release with both artifacts attached.
#
# Env knobs: VERSION (required, e.g. v0.1.0) · DRAFT=1 · FORCE_VERSION=1
#            notarization creds from .env (see .env.example)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Local credentials (gitignored; see .env.example). Notarization is on by
# default when these exist.
if [[ -f "$ROOT/.env" ]]; then
  set -a; source "$ROOT/.env"; set +a
fi

APP_NAME="${APP_NAME:?set APP_NAME, e.g. APP_NAME=Folio}"
VERSION="${VERSION:?set VERSION, e.g. VERSION=v0.1.0}"
APP="$ROOT/build/$APP_NAME.app"
OUT="$ROOT/dist"
ARCH="$(uname -m)"
# Slug for filenames — the app name may contain a space ("Recall App").
SLUG="${APP_NAME// /-}"
ZIP="$OUT/$SLUG-$VERSION-$ARCH.zip"
DMG="$OUT/$SLUG-$VERSION-$ARCH.dmg"

command -v gh >/dev/null || { echo "error: gh CLI required" >&2; exit 1; }

# 1. preflight ---------------------------------------------------------------
# VERSION is typed by hand and a tag is the permanent record of what shipped.
# Guard the two mistakes that record cannot recover from: reusing a version, and
# silently skipping one.
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { echo "error: VERSION must look like v1.2.3 (got '$VERSION')" >&2; exit 1; }

git fetch --tags --quiet origin 2>/dev/null || true
if git rev-parse "$VERSION" >/dev/null 2>&1 || gh release view "$VERSION" >/dev/null 2>&1; then
  echo "error: $VERSION already exists — releases are immutable; cut the next version" >&2
  exit 1
fi

LAST_TAG="$(git tag -l 'v*' --sort=-v:refname | head -1)"
if [[ -n "$LAST_TAG" ]]; then
  IFS=. read -r lm ln lp <<< "${LAST_TAG#v}"
  EXPECTED=("v$lm.$ln.$((lp + 1))" "v$lm.$((ln + 1)).0" "v$((lm + 1)).0.0")
  if [[ ! " ${EXPECTED[*]} " =~ " $VERSION " && -z "${FORCE_VERSION:-}" ]]; then
    echo "error: $VERSION does not follow $LAST_TAG — expected one of: ${EXPECTED[*]}" >&2
    echo "       (FORCE_VERSION=1 to skip a version deliberately)" >&2
    exit 1
  fi
fi

[[ -z "$(git status --porcelain)" ]] \
  || { echo "error: working tree is dirty — commit or stash before releasing" >&2; exit 1; }
git fetch --quiet origin main 2>/dev/null || true
if [[ -n "$(git log --oneline origin/main..HEAD 2>/dev/null)" ]]; then
  echo "error: HEAD is ahead of origin/main — push first, or the tag points at" >&2
  echo "       code nobody else has" >&2
  exit 1
fi
echo "==> releasing $APP_NAME $VERSION (previous: ${LAST_TAG:-none})"

# 2. build -------------------------------------------------------------------
echo "==> building $APP_NAME.app ($VERSION)"
mkdir -p "$OUT"
MARKETING_VERSION="${VERSION#v}" ./scripts/package-app.sh release

# The version is what a user sees in About: wrong is invisible to us and
# permanent to them. Assert it before anything is notarized, tagged, or shipped.
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ "$BUILT_VERSION" != "${VERSION#v}" ]]; then
  echo "error: built app says $BUILT_VERSION but this release is ${VERSION#v}" >&2
  echo "       (scripts/package-app.sh must honour \$MARKETING_VERSION)" >&2
  exit 1
fi
echo "    version: $BUILT_VERSION"

# A Developer ID signature is what lets a downloader open the app without
# right-click → Open. Warn loudly if we only managed ad-hoc.
if codesign -dvv "$APP" 2>&1 | grep -q 'Authority=Developer ID Application'; then
  echo "    signed:  Developer ID"
else
  echo "    WARNING: not Developer ID–signed — downloaders will hit Gatekeeper" >&2
fi

# 3. notarize (optional) -----------------------------------------------------
# notarytool only accepts .zip/.dmg/.pkg uploads; stapler only writes tickets to
# the .app/.dmg — so submit and staple are deliberately separate steps.
#
# Auth: the App Store Connect key directly when .env provides one, else a
# notarytool keychain profile. Key-first, because reading back a keychain profile
# needs a GUI login session — store-credentials reports success in a headless
# shell (CI, an agent, ssh) and then the item is nowhere to be found.
NOTARY_KEY_PATH="${NOTARY_KEY_PATH/#\~/$HOME}"
if [[ -f "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
  NOTARY_AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
  NOTARY_HOW="App Store Connect key $NOTARY_KEY_ID"
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
  NOTARY_HOW="keychain profile $NOTARY_PROFILE"
fi

submit_for_notarization() {
  xcrun notarytool submit "$1" "${NOTARY_AUTH[@]}" --wait \
    || { echo "error: notarization of $1 was not accepted" >&2; exit 1; }
}

if [[ -n "${NOTARY_HOW:-}" ]]; then
  echo "==> notarizing the app ($NOTARY_HOW)"
  ditto -c -k --keepParent "$APP" "$OUT/notarize-upload.zip"
  submit_for_notarization "$OUT/notarize-upload.zip"
  rm -f "$OUT/notarize-upload.zip"
  xcrun stapler staple "$APP"
  spctl --assess -vv "$APP" 2>&1 | sed 's/^/      /'
else
  echo "==> no notarization credentials (.env) — skipping notarization"
  echo "    (downloaders must approve the app in System Settings → Privacy & Security)"
fi

# 4. package -----------------------------------------------------------------
echo "==> packaging"
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "$APP_NAME" \
    --window-size 660 420 \
    --icon-size 110 \
    --icon "$APP_NAME.app" 180 190 \
    --app-drop-link 480 190 \
    --hide-extension "$APP_NAME.app" \
    "$DMG" "$APP" >/dev/null
else
  echo "    (create-dmg not installed — plain dmg; brew install create-dmg for the styled one)"
  STAGE="$(mktemp -d)"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
fi

if [[ -n "${NOTARY_HOW:-}" ]]; then
  echo "==> notarizing the dmg"
  submit_for_notarization "$DMG"
  xcrun stapler staple "$DMG"
fi

( cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > SHA256SUMS )
echo "    $(du -h "$ZIP" | cut -f1)  $ZIP"
echo "    $(du -h "$DMG" | cut -f1)  $DMG"

# 5. tag + release -----------------------------------------------------------
echo "==> tagging $VERSION"
git tag -a "$VERSION" -m "$APP_NAME $VERSION"
git push origin "$VERSION"

echo "==> creating GitHub release $VERSION"
GH_ARGS=(release create "$VERSION" "$ZIP" "$DMG" "$OUT/SHA256SUMS"
  --title "$APP_NAME $VERSION"
  --generate-notes)
[[ -n "${DRAFT:-}" ]] && GH_ARGS+=(--draft)
gh "${GH_ARGS[@]}"

echo "✓ released $APP_NAME $VERSION"
echo
echo "  Homebrew: update the cask's version + sha256 from:"
echo "    $OUT/SHA256SUMS"
