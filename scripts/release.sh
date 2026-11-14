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
  require_env TOSSBAR_SIGN_IDENTITY ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID
  [[ -f "$ASC_KEY_PATH" ]] || { echo "ASC_KEY_PATH does not exist" >&2; exit 1; }
}

package() {
  local version="$1"
  verify

  # macOS wants x.y.z here, so a prerelease such as 1.2.0-dev.3 becomes 1.2.0.
  # The build number tells prereleases apart.
  TOSSBAR_VERSION="${version%%-*}" \
  TOSSBAR_BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}" \
    "$ROOT/scripts/build-app.sh" release

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
