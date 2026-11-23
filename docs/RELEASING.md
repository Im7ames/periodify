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

Configure **Actions variables** `CLOUDFLARE_ACCOUNT_ID` and `PERIODIFY_WEB_URL` (the deployed HTTPS origin).

The same Android key signs phone and watch APKs. Debug keys are for local testing only. Missing production credentials fail the applicable job; there is no unsigned fallback. A Windows/Apple trusted certificate must be obtained from its provider. The Linux `.deb` has a detached `.asc` signature and the public signing key is attached to the release.

## Workflow

1. Increment `version: x.y.z+N`; `N` must monotonically increase for Android updates. Update the changelog.
2. Run `flutter analyze`, `flutter test`, and builds affected by the change.
3. Commit and push to `main`. Validation creates `vX.Y.Z` as a preview release, then explicitly dispatches `release.yml` for that tag. Existing tags are never moved.
4. Packaging checks out the immutable tag. Web deployment uses the official `cf` CLI and verifies the deployed page. All native jobs require production keys, and phone/watch certificate hashes must match.
5. The final job uploads verified installers as they become available, the web ZIP, Linux detached signature/public key, `SHA256SUMS.txt` and `updates.json`; writes a platform download table; then downloads each package again to verify its checksum.
6. Monitor Actions to terminal state. Retry only transient failures. Fix source problems in a new patch release; configure missing secrets and rerun failed jobs for setup failures.

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
