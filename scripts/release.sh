#!/usr/bin/env bash
set -euo pipefail

# Build, sign (Developer ID + hardened runtime), notarize, and package Scope as a
# distributable .dmg. This is for distribution OUTSIDE the Mac App Store.
#
# One-time setup (requires a paid Apple Developer Program membership):
#   1. Create a "Developer ID Application" certificate and install it in your
#      login keychain (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ +).
#   2. Store notarization credentials as a keychain profile named "ScopeNotary":
#        xcrun notarytool store-credentials "ScopeNotary" \
#          --apple-id "you@example.com" \
#          --team-id "ABCDE12345" \
#          --password "app-specific-password"
#      (An App Store Connect API key also works — see `notarytool store-credentials --help`.)
#
# Override defaults with env vars: SIGN_IDENTITY, NOTARY_PROFILE.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/Build/Scope.app"
DMG_PATH="$ROOT_DIR/Build/Scope.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-ScopeNotary}"

cd "$ROOT_DIR"

# --- Resolve signing identity ------------------------------------------------
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  IDENTITY="$SIGN_IDENTITY"
else
  IDENTITY="$(security find-identity -v -p codesigning \
    | grep -oE '"Developer ID Application: [^"]+"' \
    | head -1 | tr -d '"')"
fi

if [[ -z "${IDENTITY:-}" ]]; then
  echo "ERROR: No 'Developer ID Application' certificate found." >&2
  echo "       Create one in Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates," >&2
  echo "       or set SIGN_IDENTITY to the identity name/hash." >&2
  exit 1
fi
echo "Signing identity: $IDENTITY"

# --- Build the app bundle ----------------------------------------------------
"$ROOT_DIR/scripts/build-app.sh"

# --- Code sign with hardened runtime -----------------------------------------
# Sign the inner executable first, then the bundle.
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" "$APP_DIR/Contents/MacOS/Scope"
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" "$APP_DIR"

echo "Verifying signature..."
codesign --verify --strict --verbose=2 "$APP_DIR"

# --- Package as a compressed .dmg --------------------------------------------
rm -f "$DMG_PATH"
hdiutil create -volname "Scope" -srcfolder "$APP_DIR" \
  -ov -format UDZO "$DMG_PATH"

# --- Notarize and staple -----------------------------------------------------
echo "Submitting to Apple notary service (this can take a few minutes)..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_DIR"
xcrun stapler staple "$DMG_PATH"

echo "Gatekeeper assessment:"
spctl --assess --type execute --verbose=2 "$APP_DIR" || true

echo
echo "Done. Distributable build: $DMG_PATH"
