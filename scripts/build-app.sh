#!/usr/bin/env bash
# Wraps the SwiftPM executable into TossBar.app. Xcode is not required.
#
# Usage: scripts/build-app.sh [release|debug]
#
# Optional environment:
#   TOSSBAR_VERSION        CFBundleShortVersionString (x.y.z). Defaults to Info.plist.
#   TOSSBAR_BUILD_NUMBER   CFBundleVersion. Defaults to Info.plist.
#   TOSSBAR_SIGN_IDENTITY  Code signing identity. Defaults to "-" (ad-hoc). Any other
#                          identity signs with the hardened runtime and a secure
#                          timestamp, which notarization requires.
#   TOSSBAR_KEYCHAIN       Keychain that holds the signing identity.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/TossBar.app"
IDENTITY="${TOSSBAR_SIGN_IDENTITY:--}"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/TossBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TossBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

PLIST="$APP/Contents/Info.plist"
if [[ -n "${TOSSBAR_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TOSSBAR_VERSION" "$PLIST"
fi
if [[ -n "${TOSSBAR_BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $TOSSBAR_BUILD_NUMBER" "$PLIST"
fi

if [[ "$IDENTITY" == "-" ]]; then
  # Ad-hoc signature. Required for registering as a login item.
  codesign --force --deep --sign - "$APP" >/dev/null
else
  KEYCHAIN_ARGS=()
  if [[ -n "${TOSSBAR_KEYCHAIN:-}" ]]; then
    KEYCHAIN_ARGS=(--keychain "$TOSSBAR_KEYCHAIN")
  fi
  codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi

echo "Built $APP"
echo "  Run:     open \"$APP\""
echo "  Install: cp -R \"$APP\" /Applications/"
