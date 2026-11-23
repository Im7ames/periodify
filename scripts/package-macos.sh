#!/usr/bin/env bash
set -euo pipefail
: "${MACOS_CERTIFICATE_BASE64:?Missing Apple signing certificate}"
: "${MACOS_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${MACOS_SIGNING_IDENTITY:?Missing Developer ID identity}"
: "${APPLE_ID:?Missing Apple ID}"
: "${APPLE_APP_PASSWORD:?Missing notarization password}"
: "${APPLE_TEAM_ID:?Missing Apple team ID}"
KEYCHAIN="$RUNNER_TEMP/periodify.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
trap 'security delete-keychain "$KEYCHAIN" || true; rm -f "$RUNNER_TEMP/apple.p12"' EXIT
printf '%s' "$MACOS_CERTIFICATE_BASE64" | base64 --decode > "$RUNNER_TEMP/apple.p12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$RUNNER_TEMP/apple.p12" -k "$KEYCHAIN" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
flutter build macos --release
APP=build/macos/Build/Products/Release/periodify.app
find "$APP/Contents/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -exec codesign --force --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" {} \;
codesign --force --options runtime --timestamp --entitlements macos/Runner/Release.entitlements --sign "$MACOS_SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p artifacts
hdiutil create -volname Periodify -srcfolder "$APP" -ov -format UDZO artifacts/periodify-macos.dmg
codesign --sign "$MACOS_SIGNING_IDENTITY" --timestamp artifacts/periodify-macos.dmg
xcrun notarytool submit artifacts/periodify-macos.dmg --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait
xcrun stapler staple artifacts/periodify-macos.dmg
xcrun stapler validate artifacts/periodify-macos.dmg
