#!/usr/bin/env bash
set -euo pipefail

APP=build/macos/Build/Products/Release/periodify.app
test -x "$APP/Contents/MacOS/periodify" || { echo 'Run flutter build macos --release before packaging.' >&2; exit 1; }

stage=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/periodify-disk.XXXXXXXX")
keychain=''
p12=''
cleanup() {
  if [[ -n "$keychain" ]]; then security delete-keychain "$keychain" || true; fi
  if [[ -n "$p12" ]]; then rm -f "$p12"; fi
  rm -rf "$stage"
}
trap cleanup EXIT
chmod 755 "$stage"

create_disk_image() {
  mkdir -p artifacts
  ditto "$APP" "$stage/Periodify.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname Periodify -srcfolder "$stage" -ov -format UDZO "$1"
  hdiutil verify "$1"
}

if [[ ${1:-} == --unnotarized && $# == 1 ]]; then
  create_disk_image artifacts/periodify-macos-unnotarized.dmg
  exit 0
fi
if (( $# != 0 )); then
  echo 'Usage: package-macos.sh [--unnotarized]' >&2
  exit 2
fi

: "${MACOS_CERTIFICATE_BASE64:?Missing Apple signing certificate}"
: "${MACOS_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${MACOS_SIGNING_IDENTITY:?Missing Developer ID identity}"
: "${APPLE_ID:?Missing Apple ID}"
: "${APPLE_APP_PASSWORD:?Missing notarization password}"
: "${APPLE_TEAM_ID:?Missing Apple team ID}"
keychain="$RUNNER_TEMP/periodify.keychain-db"
p12="$RUNNER_TEMP/apple.p12"
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
umask 077
printf '%s' "$MACOS_CERTIFICATE_BASE64" | base64 --decode > "$p12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$keychain"
security import "$p12" -k "$keychain" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$keychain"
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
find "$APP/Contents/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -exec codesign --force --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" {} \;
codesign --force --options runtime --timestamp --entitlements macos/Runner/Release.entitlements --sign "$MACOS_SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
create_disk_image artifacts/periodify-macos.dmg
codesign --sign "$MACOS_SIGNING_IDENTITY" --timestamp artifacts/periodify-macos.dmg
xcrun notarytool submit artifacts/periodify-macos.dmg --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait
xcrun stapler staple artifacts/periodify-macos.dmg
xcrun stapler validate artifacts/periodify-macos.dmg
