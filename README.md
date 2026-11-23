# Periodify

An independent Bromcom timetable companion. Flutter powers Android, Windows, macOS, Linux and web; a small native Kotlin app runs on Wear OS.

## Use

1. On Android, Windows or macOS, press **Scrape** and sign in through Bromcom's **Microsoft** button.
2. Open **My Timetable**, select a teaching week, wait for loading to finish, and press **Scrape visible timetable or homework**. Repeat for additional weeks.
3. To import homework, reopen the portal, choose **Homework** from the section menu, and press **Scrape**. Only the displayed table is imported; no homework is submitted or modified.
4. Set period start/end times in Settings if you want the watch to identify current/upcoming lessons. The observed portal table does not supply clock times.
5. Install the companion on a paired Wear OS watch. Phone and watch must share the same application ID and signing certificate. Saving a snapshot queues it to the watch; you can also press **Sync saved timetable**.

Nothing scrapes on startup, a timer, page navigation, or from the watch. Visiting the portal loads its own pages; extracting and saving data requires the Scrape button.

Web and Linux support local JSON snapshot import/export. Browser same-origin restrictions prevent a hosted web app from reading Bromcom's login session. There is no server-side password or cookie proxy.

## Privacy

Timetables and homework are stored in application preferences on your device (browser local storage on web). They are not uploaded to Cloudflare, GitHub or an analytics service. JSON exports contain private timetable data. Microsoft credentials are entered on Microsoft's page inside the portal browser; extraction runs only on the exact Bromcom HTTPS timetable/homework URLs and captures only the relevant rendered tables. Android backups are disabled. Portal cookies may persist in the platform WebView.

## Develop

Requires Flutter 3.47.2, Dart 3.13.2, Java 17, Android SDK 36 and platform build tools. The project pins AGP 8.11.1 / Gradle 8.14.3 because the upstream WebView plugin currently uses APIs removed in AGP 9.

```sh
flutter pub get
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
cd android
./gradlew :wear:assembleDebug
```

For native desktop builds, install Flutter's platform-specific prerequisites. Windows WebView sign-in additionally requires Microsoft Edge WebView2 Runtime; Linux is a snapshot viewer.

## Release

See [docs/RELEASING.md](docs/RELEASING.md). Bump the version and build number in `pubspec.yaml`, update `CHANGELOG.md`, and push. The Build workflow verifies the source. Publishing a GitHub release for the checked commit calls the same workflow in signed release mode. The release workflow also supports a manual dry run.

## Verification limits

The live timetable and homework DOM were inspected with the account owner's permission. Tests use synthetic records only. Embedded Microsoft sign-in can be restricted by a school's Conditional Access policy; that must be checked on the intended device. Physical Wear OS sync and signed installer execution require hardware and signing credentials. Do not describe a release as verified until its workflow and device checks pass.
