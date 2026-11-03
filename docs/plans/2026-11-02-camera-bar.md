# Camera Bar Implementation Plan

> Execute with superpowers:subagent-driven-development in this session. Doctor Biz has approved the design and continuing implementation.

**Goal:** Build a minimal macOS menu bar RTSP viewer and native desktop snapshot widget sharing one selected camera.

**Architecture:** SwiftUI/AppKit hosts a single VLCKit player and camera settings. A Foundation core stores camera metadata and atomic widget snapshots. Credentials stay in Keychain; WidgetKit reads only published images and metadata from an App Group.

**Tech Stack:** Swift, Swift Package Manager for core tests, Xcode app/extension targets, VLCKit, WidgetKit, XCTest, local MediaMTX/FFmpeg RTSP fixture.

## State

- Design approved. Repository initialized on `wip/camera-bar`.
- Task 1 complete in `01f70ac`: 18 tests pass, format clean; independent spec and quality reviews approved.
- Tasks 2–3 will use one native-app implementation agent because app, player, extension, and Xcode targets share build configuration. Both sets of acceptance checks remain required.
- Tasks 2–3 in progress with native-app agent; Task 4 pending.
- Compaction count: 0.
- No signing identity available; local widget loading must be checked.
- Native desktop-control inventory failed with `Sky Computer Use native pipe startup failed`; retry after build and use Xcode UI testing for repeatable app checks.

## Task 1: Camera model and snapshot storage

Create `Package.swift`, `Sources/CameraBarCore/Camera.swift`, `Sources/CameraBarCore/CameraCatalog.swift`, `Sources/CameraBarCore/SnapshotStore.swift`, and `Tests/CameraBarCoreTests/`.

1. Write tests for RTSP-only address validation (host required; credentials preserved but never in metadata), trimmed nonempty names, camera add/edit/delete/select, persisted selection, and corrupt data errors. Run `swift test` and record expected missing behavior.
2. Implement minimal Foundation models and file-backed catalog. Store only opaque IDs and names in catalog, with credential storage owned by the app. Preserve public invariants across decoding.
3. Add failing tests for atomic snapshot round trips, mismatched-camera rejection, empty state, clearing on selection changes, and preserving original capture dates. Run tests to see failures.
4. Implement a small snapshot store usable from app and extension. A single atomic Codable document containing image data and metadata avoids image/metadata races.
5. Run `swift test` and `swift format lint --strict --recursive Sources Tests`. Review spec then quality; commit.

## Task 2: RTSP engine and native app

Create `CameraBar/` sources, `CameraBarTests/`, Xcode project configuration, and `scripts/build`.

1. Use the official stable VLCKit 3.7.3 XCFramework, pinned by archive SHA-256, rather than the alpha Swift package. Configure native app target and tests. Use macOS 14 minimum for desktop widgets. No runtime dependency on a separately installed VLC app.
2. Write failing tests for real Keychain round trips and safe error handling, plus camera state transitions and stale callback rejection. Implement the smallest state owner with one selected camera.
3. Write a real RTSP test before implementing playback; use a locally generated test pattern served over RTSP. Confirm the feature is absent, then implement live video, muted audio, bounded background snapshot capture, cancellation, and reconnect behavior.
4. Add settings for named RTSP addresses and a camera picker in the menu bar popover. Test empty state, add/edit/remove, selection persistence, live display, and connection failure via UI automation or XCTest. Never add a mock mode.
5. Build and run tests; inspect app behavior; review spec then quality; commit.

## Task 3: Native snapshot widget

Create `CameraBarWidget/` sources and extension target with matching App Group entitlements and app link handling.

1. Write failing tests for timeline entry selection, empty/corrupt snapshots, capture dates, and camera identity. Implement mapping from shared snapshot record to widget presentation.
2. Build small and medium widget layouts with camera name, image, capture time, and open-viewer link. Share the core store; never copy credential state into the extension.
3. Test app publication through actual shared files and widget read path. Build embedded extension and inspect its Info.plist, entitlements, and registration. Try adding the native widget locally.
4. Review spec then quality; commit.

## Task 4: Verification and delivery

Create `scripts/check`, `scripts/test-rtsp`, `README.md`, and any required dependency bootstrap scripts with help and clear diagnostics.

1. Assemble canonical check: format/lint, core tests, app/extension build and tests, real RTSP test, UI smoke checks. Record logs under ignored `.build/` and fail with useful pointers.
2. Run the complete check and fix failures using failing regression tests. Check clean logs, safe credential handling, offline behavior, rapid camera switching, and app shutdown.
3. Obtain independent final spec and code review; fix and re-review findings. Document launch instructions, dependency licenses, and exact signing/widget limitations.
4. Update plan and gotchas, commit, and provide the built app location with verification results. Do not merge to main without instruction.
