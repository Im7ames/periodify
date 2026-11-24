# Periodify 0.1.9

- Add, name, and time as many periods as your school uses, with matching Bromcom labels on the timetable and watch.
- Carry over existing bell times into the period editor and sync period settings with your account.
- Use the Periodify logo in the app, launchers, Windows installer, and browser and installed web app icons.

# Periodify 0.1.8

- Sync encrypted timetable snapshots, homework, and preferences across devices with a Periodify account code.
- Check for updates in the app and hand verified downloads to the platform installer. Restart directly on Windows and reload on the web.
- Capture Bromcom lesson colours and use softer accents in light mode, dark mode, and on Wear OS.

# Periodify 0.1.7

- Configure a repeating timetable and capture its teaching weeks in one guided Bromcom session.
- Show repeats on the phone, desktop, web, and paired Wear OS watch.
- Open Appearance, Timetable, and Data on separate Settings pages.
- Include the Periodify information and downloads page in the web build.

# Periodify 0.1.6

- Integrate Timetable, Watch, and Settings into a custom Windows title bar with window controls.
- Use the new squircle browser favicon and switch between light and dark artwork as the system theme changes.

# Periodify 0.1.5

- Publish an unsigned Windows installer and an unnotarized macOS disk image as labelled previews.
- Keep signing Android, Wear OS, and Linux packages with the existing keys.

# Periodify 0.1.4

- Use a shared build workflow for CI and tagged releases, with a manual dry run.
- Publish signed Android APKs and an Android App Bundle. Verify installer downloads before attaching the update manifest.
- Keep the Windows WebView build compatible with Visual Studio 2026.
- Keep unsigned Windows and macOS builds out of releases while the runners verify compilation.

# Periodify 0.1.3

- Check Windows and macOS compilation before package signing. Unavailable downloads link to their build status.

# Periodify 0.1.2

- Make Cloudflare deployment opt-in. GitHub Actions still builds the web ZIP and release packages.

# Periodify 0.1.1

- Fix extraction of the GitHub Actions web build before Cloudflare deployment.
- Record and verify the source commit and release tag on the deployed site.
- Preserve compatibility with the existing Linux signing key generated on Windows.

# Periodify 0.1.0 — initial preview

- Flutter app for Android, Windows, macOS, Linux and web, with light, dark and system themes.
- Manual Bromcom timetable and visible homework-table import after Microsoft sign-in.
- Offline day views, multi-week snapshots, snapshot import/export and configurable bell times.
- Native Wear OS companion with local timetable caching and phone-to-watch Data Layer sync.
- Release automation for signed packages, SHA-256 checksums, update manifests and download tables.

This is a preview. Portal markup was inspected in an authenticated browser; sign-in inside the packaged WebViews and physical phone/watch sync still require device validation. Web and Linux view imported snapshots. Homework import covers the currently displayed table, not attachments or submission actions. Release signing and Cloudflare deployment require the secrets documented in docs/RELEASING.md. Each installer is listed once its signing job passes.
