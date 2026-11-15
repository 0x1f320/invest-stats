#!/usr/bin/env bash
# Wraps the SwiftPM executable into TossBar.app. Xcode is not required.
#
# Usage: scripts/build-app.sh [release|debug]
#
# Optional environment:
#   TOSSBAR_VERSION        CFBundleShortVersionString (x.y.z). Defaults to Info.plist.
#   TOSSBAR_BUILD_NUMBER   CFBundleVersion. Defaults to Info.plist.
#   TOSSBAR_RELEASE_VERSION
#                          Full release version, such as 1.2.0-dev.3, stored as
#                          TossBarReleaseVersion. The in-app updater compares it with GitHub
#                          Releases; builds without it never update themselves.
#   TOSSBAR_SIGN_IDENTITY  Code signing identity. Defaults to "-" (ad-hoc). Any other
#                          identity signs with the hardened runtime and a secure
#                          timestamp, which notarization requires.
#   TOSSBAR_KEYCHAIN       Keychain that holds the signing identity.
#   TOSSBAR_PROVISION_PROFILE
#                          Developer ID provisioning profile for dev.tossbar.TossBar. With a
#                          real identity, it is embedded and the app is signed with
#                          Resources/TossBar.entitlements, which grants the keychain access
#                          group for the iCloud Keychain. Ignored for ad-hoc builds, which
#                          cannot carry that entitlement.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/TossBar.app"
IDENTITY="${TOSSBAR_SIGN_IDENTITY:--}"
PROFILE="${TOSSBAR_PROVISION_PROFILE:-}"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/TossBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TossBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

PLIST="$APP/Contents/Info.plist"
if [[ -n "${TOSSBAR_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TOSSBAR_VERSION" "$PLIST"
fi
if [[ -n "${TOSSBAR_RELEASE_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :TossBarReleaseVersion string $TOSSBAR_RELEASE_VERSION" "$PLIST"
fi
if [[ -n "${TOSSBAR_BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $TOSSBAR_BUILD_NUMBER" "$PLIST"
fi

if [[ "$IDENTITY" == "-" ]]; then
  # Ad-hoc signature. Required for registering as a login item.
  if [[ -n "$PROFILE" ]]; then
    echo "Ignoring TOSSBAR_PROVISION_PROFILE: ad-hoc builds cannot use it." >&2
  fi
  codesign --force --deep --sign - "$APP" >/dev/null
else
  SIGN_ARGS=(--force --options runtime --timestamp --sign "$IDENTITY")
  if [[ -n "${TOSSBAR_KEYCHAIN:-}" ]]; then
    SIGN_ARGS+=(--keychain "$TOSSBAR_KEYCHAIN")
  fi
  if [[ -n "$PROFILE" ]]; then
    [[ -f "$PROFILE" ]] || { echo "TOSSBAR_PROVISION_PROFILE does not exist" >&2; exit 1; }
    cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
    SIGN_ARGS+=(--entitlements "$ROOT/Resources/TossBar.entitlements")
  fi
  codesign "${SIGN_ARGS[@]}" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi

echo "Built $APP"
echo "  Run:     open \"$APP\""
echo "  Install: cp -R \"$APP\" /Applications/"
