# Project notes

- Doctor Biz chose a native macOS WidgetKit widget, accepting system-controlled refresh timing. The menu bar app captures images; the widget reads the shared latest snapshot and capture date. Keep the app running for updates.
- Local setup on 2026-11-02: Xcode is available, but `security find-identity -v -p codesigning` reports no valid identities. Verify local widget registration; do not claim signed distribution works.
- `~/.codex/docs/local.md` is missing. No existing project or code was present at session start.
- Use stable VLCKit 3.7.3 from VideoLAN's production archive. Its current Swift package points to an alpha build. Downloaded archive SHA-256: `019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d`.
- `CameraCatalog` expects one owning thread; the app owns it on the main actor. Clear shared snapshots on selection changes and reject callbacks from old player sessions before publication.
