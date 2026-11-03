# Project notes

- Doctor Biz chose a native macOS WidgetKit widget, accepting system-controlled refresh timing. The menu bar app captures images; the widget reads the shared latest snapshot and capture date. Keep the app running for updates.
- Local setup on 2026-11-02: Xcode is available, but `security find-identity -v -p codesigning` reports no valid identities. Verify local widget registration; do not claim signed distribution works.
- `~/.codex/docs/local.md` is missing. No existing project or code was present at session start.
