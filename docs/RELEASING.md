# Release setup

The pipeline never generates or rotates signing keys. Preserve the application ID `com.im7ames.periodify`, Windows installer AppId, Android keystore, and platform signing identities across releases. Back up keys outside the repository. Do not paste private key material into issues or chat.

Configure these repository **Actions secrets**:

| Platform | Secrets |
| --- | --- |
| Android and Wear OS | `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` |
| Windows Authenticode | `WINDOWS_PFX_BASE64`, `WINDOWS_PFX_PASSWORD` |
| macOS Developer ID + notarization | `MACOS_CERTIFICATE_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID` |
| Linux detached OpenPGP signature | `LINUX_GPG_PRIVATE_KEY` (armored private key), `LINUX_GPG_PASSPHRASE` |
| Cloudflare | `CLOUDFLARE_API_TOKEN` with Workers Scripts edit permissions for the selected account |

Cloudflare deployment is opt-in. Set the `CLOUDFLARE_API_TOKEN` secret and `CLOUDFLARE_ACCOUNT_ID` and `PERIODIFY_WEB_URL` variables first. Then set the `PERIODIFY_DEPLOY_WEB` Actions variable to `true`. Leave it blank to skip Cloudflare while still building and publishing the web ZIP.

The original Linux key was generated on Windows with a trailing carriage return in its passphrase. Set the `LINUX_GPG_PASSPHRASE_SUFFIX_CR` Actions variable to `true` for that key. Keep the stored passphrase itself as the printable text.

The same Android key signs the phone APK, Wear OS APK and Android App Bundle. Debug builds are for testing. Missing Android or Linux credentials fail the release build. Windows and macOS compilation runs independently, and downloads require their trusted signing credentials. The Linux `.deb` has a detached `.asc` signature and the public signing key is attached to the release.

Windows and macOS compilation is checked separately from signing. A successful compilation is visible in Actions even if credentials are missing. For Windows, the current workflow accepts a PFX with the private key for a trusted Authenticode certificate. A hardware-backed certificate or managed signing service needs its provider's signing integration instead. For macOS, export a **Developer ID Application** certificate and private key to a password-protected `.p12` and configure the Apple notarization credentials above. Add credentials through the repository's Actions secret settings.

## Workflow

1. Increment `version: x.y.z+N`; `N` must monotonically increase for Android updates. Update the changelog.
2. Run `flutter analyze`, `flutter test`, and builds affected by the change.
3. Commit and push. **Build Periodify** runs on pushes and pull requests. It builds and tests the web app, builds debug Android and Wear OS APKs, and compiles on Windows, macOS and Linux.
4. Publish a GitHub release for the checked commit with tag `vX.Y.Z`. **Publish Periodify release** verifies the tag and version and calls the same build workflow with the signing credentials. Keep existing tags on their original commits.
5. The publish job attaches available installers, the web ZIP, the Linux detached signature and public key, and `SHA256SUMS.txt`. It verifies the uploaded bytes, attaches `updates.json`, and updates the download table. When enabled, Cloudflare deploys the verified web ZIP.
6. Use **Run workflow** on the release workflow with **dry_run** checked to save a `release-preview` artifact without editing a release. To attach packages after adding credentials, select the existing release tag as the ref, enter that same tag as `release_tag`, and turn off **dry_run**. Retry transient failures and use a new patch version for source fixes.

`updates.json` is a versioned update discovery manifest, not an automatic installer. It provides asset URLs, sizes and SHA-256 hashes. Updates remain user-installed. Android accepts replacements only with the same signing key; Windows uses the stable installer AppId; macOS uses the existing Developer ID.

## Device acceptance checks

- Microsoft sign-in/MFA returns to Bromcom in the packaged Android WebView.
- Scrape selected week, verify dates/rooms, restart offline, and confirm persistence.
- Cancel login and fail a scrape; prior data remains unchanged.
- Import multiple weeks and verify a re-import updates the selected week without deleting other weeks.
- Export from Android's document picker and import into the hosted web viewer.
- Pair real phone/watch, sync, disconnect, and verify cached timetable plus bell-time current/upcoming states.
- Clear phone data and reconnect watch; cached watch data must clear.
- Validate signed update installation over the preceding version on every platform.
