# Project notes

- Doctor Biz chose a native macOS WidgetKit widget, accepting system-controlled refresh timing. The menu bar app captures images; the widget reads the shared latest snapshot and capture date. Keep the app running for updates.
- Local setup on 2026-11-02: Xcode is available, but `security find-identity -v -p codesigning` reports no valid identities. Verify local widget registration; do not claim signed distribution works.
- `~/.codex/docs/local.md` is missing. No existing project or code was present at session start.
- Use stable VLCKit 3.7.3 from VideoLAN's production archive. Its current Swift package points to an alpha build. Downloaded archive SHA-256: `019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d`.
- `CameraCatalog` expects one owning thread; the app owns it on the main actor. Clear shared snapshots on selection changes and reject callbacks from old player sessions before publication.
- Doctor Biz explicitly approved a local build with signing instructions on 2026-11-02; no Apple Developer team is available. Deliver the native extension and document signing setup, without claiming a signed desktop widget was activated.
- On this macOS version, `containerURL(forSecurityApplicationGroupIdentifier:)` can return a path for unsigned code. Writing there triggers an unrelated-looking cross-app data permission prompt. Check the running signature's team and App Group entitlement before resolving the container; an unsigned viewer should show signing setup guidance.
- VLCKit defaults to verbose logging that includes RTSP requests; `loggers = nil` alone is insufficient. Explicitly set verbosity to zero. Its snapshot API can raise Objective-C exceptions when video output disappears, so bridge that failure into an ordinary Swift error.
