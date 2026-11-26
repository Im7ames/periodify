# Periodify

An independent Bromcom timetable companion. Flutter powers Android, Windows, macOS, Linux and web; a small native Kotlin app runs on Wear OS.

## Use

1. On Android, Windows or macOS, press **Scrape** and sign in through Bromcom's **Microsoft** button.
2. Open **My Timetable**, select a teaching week, wait for loading to finish, and press **Scrape**. For a repeating timetable, set the number of weeks in **Settings → Timetable** before opening Bromcom. Follow the Week A, Week B, and later prompts in one session.
3. To import homework, reopen the portal, choose **Homework** from the section menu, and press **Scrape**. Only the displayed table is imported; no homework is submitted or modified.
4. Add named periods with start and end times in **Settings → Timetable**. Match the name to a Bromcom label or link a different label in the editor, for example **Afternoon tutorial** linked to **P7**. The app and paired watch use the names and times for matching lessons.
5. Install the companion on a paired Wear OS watch. Phone and watch must share the same application ID and signing certificate. Saving a snapshot queues it to the watch; you can also press **Sync saved timetable**.

Nothing scrapes on startup, a timer, page navigation, or from the watch. Visiting the portal loads its own pages; extracting and saving data requires the Scrape button.

Press **Today** to jump back to the current date. Open **Settings → Appearance** to preview and choose a timetable layout for this device.

On Android, open your launcher's widget picker and look under **Periodify** for **Today’s timetable** and **Next lesson**. Long-press an added widget to resize it. Tap it to open today's timetable in the app. Widgets show saved lessons, including period times you’ve configured, directly on your home screen.

On Wear OS, swipe or turn the crown to scroll through the timetable. Lesson colours and times appear on the left, with rooms on the right.

Add **Today’s timetable** from the watch’s tile picker to see the current and upcoming lessons at a glance. The tile shows times and rooms from the saved timetable. Tap **Full timetable** for all lessons.

To add **Now and next**, edit your watch face and choose it from Periodify for a slot that supports short text. With period times set and synced, it shows the current and next lessons as short codes, such as `MAT›ENG`. A dash means there’s no lesson in that position. Tap the complication to open the watch timetable.

Web and Linux support local JSON snapshot import/export. Browser same-origin restrictions prevent a hosted web app from reading Bromcom's login session. There is no server-side password or cookie proxy.

The information and downloads page ships at `/landing/` alongside the Flutter web app.

## Privacy

By default timetables and homework stay in application preferences on your device. **Settings → Account** lets you opt in to encrypted sync. Enter the generated sync code on each device you want to connect. Keep a private copy of the code, since it unlocks your account. The Cloudflare Worker stores encrypted snapshots and settings. The code itself and your Microsoft or Bromcom credentials stay on your devices. You can delete the cloud copy from the Account page.

JSON exports contain private timetable data. Microsoft credentials are entered on Microsoft's page inside the portal browser. Extraction reads the rendered timetable and homework tables only when you press Scrape. Android backups are disabled. Portal cookies may persist in the platform WebView.

## Updates

Periodify checks for updates and offers an action when a newer release is ready. Windows can restart into the new version and web can reload once the host serves a new build. Android and Wear OS use the device's installer and permissions. Linux can install with administrator approval and restart. macOS opens the verified disk image for installation.

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
