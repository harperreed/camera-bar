# Security monitor design and implementation plan

**Goal:** Give Camera Bar a distinct app icon and a polished native interface based on Doctor Biz's reference: “a simple security monitor.”

**Architecture:** Retain SwiftUI/AppKit, WidgetKit, VLCKit and the existing camera state. Visual changes must not change playback ownership, credential storage, snapshot timing, or URL handling.

**Design:** Graphite housing, a recessed black display, soft white labels and a restrained green indicator only when live. Clear native SF typography; small monospaced timestamps where useful. The camera image occupies the main space. A simple monitor silhouette with a small power lamp connects the app icon, menu bar and empty states. No scanlines over video, flashing lights, fake recording indicators, ornamental dashboards or terminal styling. Native controls preserve keyboard and accessibility behavior. The widget says snapshot and shows its capture date, never live.

**Context:** Doctor Biz opens the menu bar for a quick check of one selected camera. Settings manage a few cameras. Avoid adding more steps or features.

**Palette:** Housing #24292A, display #101415, text #EEF1EC, secondary #A7B0AB, live #97C49C. Green is a small status detail, not a wash over content. Respect text contrast and reduced motion; no decorative animation needed.

## Implementation

1. Build a deterministic monitor app icon with a reproducible native drawing script; generate all required macOS AppIcon asset sizes. Add a crisp template menu bar mark. Wire the asset catalog into project.yml and regenerate the Xcode project. Verify the compiled bundle contains its app icon.
2. Refine CameraBar/Views.swift and app window/popover dimensions. Use a compact header, large recessed video surface, one status footer, clear empty/connecting/error states, and organized camera settings/editor. Preserve current accessibility names and camera lifecycle behavior. Share only useful visual constants in Shared; do not duplicate camera data.
3. Refine CameraBarWidget/CameraBarWidget.swift using the same visual language, retaining readable actual capture dates, truthful snapshot labeling and small/medium layouts.
4. Keep existing unit/integration tests. Add meaningful UI assertions or screenshots for affected states rather than tests of color constants. Run scripts/check, inspect real UI screenshots and built icon. Any functional additions require a failing test first. Document environment blockers explicitly.
5. Review spec compliance, then code quality, fix findings, and commit task-sized changes. Do not publish another version tag as part of this visual task.

## Status

- Visual implementation complete; actual app UI verification passed during the Sparkle follow-up on 2026-11-09.
- Work branch: feat/security-monitor-design, same checkout.
- Compaction count: 0 for this implementation phase.
- Added original AppKit-drawn monitor artwork, all ten macOS icon sizes and a template menu mark. The compiled app contains AppIcon.icns and correct bundle icon metadata.
- Viewer now sizes to its content with a recessed display; settings/editor retain native controls and accessibility names. Medium widget uses image left and metadata right after render review showed wasted image space in the stacked layout. Small widget remains stacked.
- Independent spec and code-quality reviews passed, including the medium layout refinement.
- Verification on 2026-11-09: 18 core tests and all 14 real native/RTSP tests passed. Canonical CLI, formatting, shell, workflow and release-tool checks passed. Final scripts/build and strict deep signature verification passed. Existing VLCKit and host Xcode diagnostics remain.
- scripts/check reached the UI stage, but XCTest could not initialize: macOS required authentication for “Enable UI Automation.” Two attempts timed out before executing testCameraLifecycle. Doctor Biz has been asked to approve the system prompt; do not claim a passing full suite or actual app screenshot review yet.
- Temporary renders of the real widget content at small/medium sizes, with a real RTSP fixture frame, were visually reviewed under .build/design-previews/. These are visual previews, not desktop WidgetKit activation evidence. No application mock mode was added.
- Follow-up: Doctor Biz approved automation. The test needed to explicitly target the built app because the installed copy owned the URL handler. The corrected lifecycle passed and its scoped screenshot attachments were inspected under .build/sparkle-ui-success/. Doctor Biz subsequently requested publication; v1.0.1 passed GitHub signing/notarization and independent downloaded-artifact verification. Desktop widget gallery rendering remains unverified.
