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
