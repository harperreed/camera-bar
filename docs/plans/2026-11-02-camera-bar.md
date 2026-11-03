# Camera Bar Implementation Plan

> Execute with superpowers:subagent-driven-development in this session. Doctor Biz has approved the design and continuing implementation.

**Goal:** Build a minimal macOS menu bar RTSP viewer and native desktop snapshot widget sharing one selected camera.

**Architecture:** SwiftUI/AppKit hosts a single VLCKit player and camera settings. A Foundation core stores camera metadata and atomic widget snapshots. Credentials stay in Keychain; WidgetKit reads only published images and metadata from an App Group.

**Tech Stack:** Swift, Swift Package Manager for core tests, Xcode app/extension targets, VLCKit, WidgetKit, XCTest, local MediaMTX/FFmpeg RTSP fixture.

## State

- Design approved. Repository initialized on `wip/camera-bar`.
- Task 1 complete in `01f70ac`: 18 tests pass, format clean; independent spec and quality reviews approved.
- Tasks 2–3 complete in `0a7b6af`: native app, RTSP player, native widget extension, and real integration/UI tests. Independent spec and quality reviews approved.
- Task 4 complete in `da652f4`: reproducible dependency bootstrap, build, real RTSP fixture, canonical check, and signing instructions. Final verification passed; details below.
- Compaction count: 1.
- No signing identity available. Doctor Biz explicitly chose "build locally and document the signing step". Verify extension packaging; signed desktop activation is a documented user setup step, not a completion claim.
- Native desktop-control inventory failed twice with `Sky Computer Use native pipe startup failed`; real XCTest UI testing provides repeatable app checks and popover screenshots.

## Delivery verification

- `scripts/check` exited 0 on 2026-11-02: strict Swift formatting, shell syntax, 18 core tests, 14 native/RTSP tests, one complete UI lifecycle test, and local app/extension build.
- Final XCTest result bundles report no failures, skips, or runtime warnings. The installed Xcode emits the host/service diagnostics documented in README; final native, UI, and build logs contain no compiler warnings.
- Native tests decode real H.264 RTSP streams at 10 fps, 1 fps, and warmed 0.25 fps. They cover image pixels, cancellation, rapid switching, bounded offline failure, snapshot retention, real Keychain/files, and background/live lifetime.
- Actual UI automation covers add/select/edit/remove, live viewing, selection persistence, cold widget-link launch, offline state, and retry control. Inspected the captured viewer and real decoded frame visually. A deliberate failure separately proved test-owned catalog and Keychain cleanup; final catalog is empty and the fixture listener stopped.
- Independently verified the finished app with `codesign --verify --deep --strict`. The embedded extension has the WidgetKit extension identifier and matching App Group entitlements/settings. This verifies local packaging, not signed desktop activation.
- Final logs: `.build/final-check-run.log`, `.build/check-*.log`, `.build/service-tests.log`, `.build/ui-tests.log`, and `.build/app-build.log`. Final result bundles end in `Test-CameraBarServices-2026.11.02_21-21-05--0600.xcresult` and `Test-CameraBarUI-2026.11.02_21-22-22--0600.xcresult` under `.build/xcode/Logs/Test/`.
- Built app: `.build/xcode/Build/Products/Debug/CameraBar.app`. Leave the committed work on `wip/camera-bar`; no merge or remote publication requested.

## Remaining setup and limits

- Release blocker: native desktop widget activation still requires a real Apple signing team and matching registered App Group. Doctor Biz explicitly accepted local delivery with these steps documented in README. Sign and verify the desktop widget before distribution.
- Moderate compatibility limit: cameras whose initial decoding exceeds the roughly 15-second acquisition deadline can time out. Low-frame-rate capture is tested, but the warmed sparse-stream test does not prove cold startup within that deadline. No physical camera was provided; validation used real local RTSP streams.
- WidgetKit controls refresh timing; Camera Bar requests fresh snapshots about every five minutes while running. It is not a live-video widget.

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
