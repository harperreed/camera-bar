# Camera Bar design

Approved by Doctor Biz on 2026-11-02.

A native macOS SwiftUI/AppKit menu bar app opens a live RTSP video popover. Settings register, edit, and delete a small list of cameras. A single persisted selection drives the popover and native WidgetKit extension. Audio is muted. No recording, cloud service, or camera grid.

VLCKit decodes the selected RTSP stream. The menu bar app captures a snapshot periodically while running and when viewing a camera, then publishes an atomic snapshot record to an App Group container. The widget only reads the camera name, image, and capture date; it does not receive camera credentials. It shows the age of the image and links back to the viewer. WidgetKit schedules presentation updates; refresh requests are hints, not guarantees.

Camera metadata is local. Full RTSP addresses, including possible credentials or sensitive query parameters, live in macOS Keychain. Changing cameras clears the old camera's shared snapshot before starting the new stream. Errors show a safe message; the last image for the same camera keeps its original timestamp.

When the popover closes, live playback stops after any needed snapshot capture. Periodic background captures have bounded connection time and stop afterward. App shutdown stops capture. Offline cameras cannot leave a capture running forever. Snapshot publication must reject late callbacks from an earlier camera.

Verification covers URL validation, persistence and selection, snapshot identity and timestamps, real local RTSP decoding and snapshots, app settings/viewer usage, and native widget packaging/loading. Build and signing limitations are reported separately from passing tests.
