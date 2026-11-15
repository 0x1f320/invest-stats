#!/usr/bin/env bash
# Release steps that semantic-release runs through @semantic-release/exec.
#
# Usage:
#   scripts/release.sh verify               Checks that signing and notarization are configured.
#   scripts/release.sh package <version>    Builds, signs, notarizes and zips the app into
#                                           build/release/TossBar-<version>.zip.
#   scripts/release.sh published <version>  Exposes the released version to later workflow steps.
#
# Environment (set by .github/workflows/release.yml):
#   TOSSBAR_SIGN_IDENTITY  Developer ID Application identity.
#   TOSSBAR_KEYCHAIN       Keychain that holds the identity.
#   TOSSBAR_PROVISION_PROFILE
#                          Developer ID provisioning profile; grants the iCloud Keychain access group.
#   ASC_KEY_PATH           App Store Connect API key (.p8) used by notarytool.
#   ASC_KEY_ID             Its key ID.
#   ASC_ISSUER_ID          Its issuer ID.
#   GITHUB_RUN_NUMBER      Becomes CFBundleVersion, so every build has a larger number.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/TossBar.app"
OUT="$ROOT/build/release"

require_env() {
  local missing=()
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || missing+=("$name")
  done
  if (( ${#missing[@]} )); then
    echo "Missing environment: ${missing[*]}" >&2
    exit 1
  fi
}

verify() {
  require_env TOSSBAR_SIGN_IDENTITY TOSSBAR_PROVISION_PROFILE ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID
  [[ -f "$ASC_KEY_PATH" ]] || { echo "ASC_KEY_PATH does not exist" >&2; exit 1; }
  [[ -s "$TOSSBAR_PROVISION_PROFILE" ]] || { echo "TOSSBAR_PROVISION_PROFILE is missing or empty" >&2; exit 1; }
}

package() {
  local version="$1"
  verify

  # macOS wants x.y.z here, so a prerelease such as 1.2.0-dev.3 becomes 1.2.0.
  # The build number tells prereleases apart.
  TOSSBAR_VERSION="${version%%-*}" \
  TOSSBAR_BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}" \
    "$ROOT/scripts/build-app.sh" release

  # Without the keychain access group, the iCloud Keychain option would silently disappear.
  if ! codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q keychain-access-groups; then
    echo "The signed app is missing the keychain-access-groups entitlement." >&2
    exit 1
  fi
  smoke_test

  rm -rf "$OUT"
  mkdir -p "$OUT"

  local submission="$OUT/notarize.zip"
  ditto -c -k --keepParent "$APP" "$submission"

  echo "Submitting for notarization..."
  local result
  result="$(xcrun notarytool submit "$submission" \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
    --wait --output-format json)" || true
  echo "$result"

  local status id
  status="$(plutil -extract status raw -o - - <<<"$result" 2>/dev/null || true)"
  id="$(plutil -extract id raw -o - - <<<"$result" 2>/dev/null || true)"
  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization failed with status '${status:-unknown}'." >&2
    if [[ -n "$id" ]]; then
      xcrun notarytool log "$id" \
        --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" >&2 || true
    fi
    exit 1
  fi
  rm -f "$submission"

  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"

  ditto -c -k --keepParent "$APP" "$OUT/TossBar-$version.zip"
  echo "Packaged $OUT/TossBar-$version.zip"
}

# macOS kills an app at launch when its restricted entitlements don't match the embedded
# profile, so launch it once and make sure it is still running a few seconds later.
smoke_test() {
  "$APP/Contents/MacOS/TossBar" >/dev/null 2>&1 &
  local pid=$!
  sleep 5
  if ! kill -0 "$pid" 2>/dev/null; then
    wait "$pid" || true
    echo "The signed app exited right after launch; check the entitlements and the profile." >&2
    exit 1
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

published() {
  local version="$1"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "version=$version" >>"$GITHUB_OUTPUT"
  fi
}

case "${1:-}" in
  verify) verify ;;
  package) package "${2:?version required}" ;;
  published) published "${2:?version required}" ;;
  *)
    echo "Usage: $0 verify | package <version> | published <version>" >&2
    exit 2
    ;;
esac
