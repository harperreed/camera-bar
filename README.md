# Camera Bar

A small macOS menu bar RTSP viewer with a native WidgetKit snapshot widget. Pick one camera; the viewer and widget use that selection. Playback is muted. No recording, grids, or cloud service.

## Build and run

Requires macOS 14 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). On a development Mac:

```sh
brew install xcodegen
scripts/build
open .build/xcode/Build/Products/Debug/CameraBar.app
```

The build script downloads stable VLCKit 3.7.3 from VideoLAN and verifies its pinned SHA-256 before extraction. The app bundles VLCKit; VLC does not need to be installed. `scripts/build --help` lists signing options; `scripts/build --signed DEVELOPMENT_TEAM=YOUR_TEAM_ID` uses normal development signing. Build outputs and large dependencies stay in `.build/` and `Vendor/`; `project.yml` generates the checked-in `CameraBar.xcodeproj`.

Click the camera icon in the menu bar, open settings, and add your camera's RTSP address. Complete addresses, including passwords and query tokens, stay in Keychain. The catalog stores only camera IDs, names, and selection under `~/Library/Application Support/CameraBar/`. A camera's display name appears in the widget; do not put passwords in names.

Opening the viewer connects immediately. Closing it ends live playback after a bounded snapshot attempt. While Camera Bar runs, it briefly connects about every five minutes to capture a new widget image. Each connection and capture attempt has an approximately 15-second deadline; very slow camera startup can miss that window. Failed captures keep the last image and its original capture time. Changing cameras clears the old image. Quitting stops updates. The widget's displayed time is the actual successful capture time; WidgetKit controls when the desktop refreshes.

## Native widget signing

The default script makes an ad hoc local build suitable for the viewer. A working desktop widget requires your Apple development signing and a registered App Group; ad hoc builds do not establish a supported shared-container entitlement. Camera Bar reports unavailable widget sharing instead of silently writing a separate unshared file.

1. Open `CameraBar.xcodeproj` in Xcode. Select your development team for both `CameraBar` and `CameraBarWidget`. To keep signing settings across `scripts/build` runs, save the team and bundle IDs in `project.yml`; the script regenerates the Xcode project.
2. Set unique bundle IDs for both targets and register an App Group in your developer account. Set `CAMERA_BAR_APP_GROUP` to that exact identifier on both targets (default: `group.com.harper.camera-bar`). Both entitlements and Info.plist read that setting. Persist it in `project.yml`, or pass `CAMERA_BAR_APP_GROUP=your.registered.group` to `scripts/build --signed` alongside `DEVELOPMENT_TEAM=YOUR_TEAM_ID`.
3. Enable App Groups for both signing profiles, build and run the signed app, then add **Camera Bar** from macOS's widget gallery. Select a camera and keep the app running.

A local build verifies the embedded extension. Signed desktop activation still needs a suitable signing identity and matching App Group profiles.

## Verification

Install `ffmpeg` and `mediamtx` for the real RTSP fixture:

```sh
brew install ffmpeg mediamtx
scripts/check
```

Checks cover core tests, Swift formatting, native Keychain/file tests, actual RTSP decoding and image pixels, camera cancellation, background playback lifetime, and the actual UI camera lifecycle. Native tests use disposable Keychain IDs and files. UI tests add uniquely named local cameras through the ordinary settings UI, remove their own records even after failures, and restore the prior camera selection and running state. Run UI tests on a logged-in macOS desktop with Accessibility permission for Xcode's test runner; they must not run against a session where changing the selected camera would interrupt your work.

`scripts/test-rtsp --serve` runs just the local fixture at `rtsp://127.0.0.1:18554/live`. Stop it with Ctrl-C. `scripts/test-rtsp --ui` runs UI tests against that fixture. Scripts refuse an occupied port and terminate only processes they started. Logs and XCTest attachments live in `.build/`.

On the development Mac, Xcode reports mismatched CoreDevice/CoreSimulator components, an AppIntents metadata notice, and system service diagnostics from `linkd` and `DetachedSignatures`. These are retained in the full logs. Update the Xcode platform components to resolve the host installation messages. VLCKit also reports that its snapshot color conversion uses the CPU; the integration tests verify the resulting image pixels. These diagnostics are separate from compiler errors and test failures.

## Dependency license

VLCKit 3.7.3 is dynamically linked and distributed under LGPL 2.1 or later; its bundled license is in `THIRD_PARTY_NOTICES.txt`. Source and build instructions are available from [VideoLAN VLCKit](https://code.videolan.org/videolan/VLCKit) and [VLC](https://code.videolan.org/videolan/vlc). The pinned binary archive is `VLCKit-3.7.3-319ed2c0-79128878.tar.xz`, SHA-256 `019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d`. Preserve the license and applicable source/relinking obligations when distributing a signed app; this repository currently supplies local development builds.
