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

For UniFi Protect's plain RTSP output, use `rtsp://<console>:7447/<stream-token>`. Port `7441` serves RTSPS, so changing only `rtsps://` to `rtsp://` will not work. Keep the same stream token and omit `?enableSrtp` when using the plain RTSP endpoint. Camera Bar currently accepts plain RTSP only. See [Ubiquiti's port reference](https://help.ui.com/hc/en-us/articles/218506997-Required-Ports-Reference).

Opening the viewer connects immediately. Closing it ends live playback after a bounded snapshot attempt. While Camera Bar runs, it briefly connects about every five minutes to capture a new widget image. Each connection and capture attempt has an approximately 15-second deadline; very slow camera startup can miss that window. Failed captures keep the last image and its original capture time. Changing cameras clears the old image. Quitting stops updates. The widget's displayed time is the actual successful capture time; WidgetKit controls when the desktop refreshes.

## Native widget signing

The default script makes an ad hoc local build suitable for the viewer. The widget needs Apple signing and an authorized shared App Group. Camera Bar reports unavailable widget sharing when its running signature cannot establish group membership.

For this macOS-only app, a Developer ID certificate and an App Group named `YOUR_TEAM_ID.com.harper.camera-bar` are sufficient for signing and shared-container access. Apple verifies the team prefix against the signature; this form needs neither a provisioning profile nor registration in the developer portal. The `group.` form instead requires a matching provisioning profile. See [Apple's App Group requirements](https://developer.apple.com/documentation/xcode/accessing-app-group-containers).

For a local signed Release build, make the certificate and private key available in a keychain on your user search list, then substitute your team and certificate SHA-1 below. `security find-identity -v -p codesigning` lists available identities. Keep private keys and passwords outside the repository.

```sh
scripts/bootstrap
xcodebuild -project CameraBar.xcodeproj -scheme CameraBar \
  -configuration Release -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath .build/signed-xcode \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID CODE_SIGN_IDENTITY=YOUR_CERTIFICATE_SHA1 \
  CAMERA_BAR_APP_GROUP=YOUR_TEAM_ID.com.harper.camera-bar \
  ENABLE_HARDENED_RUNTIME=YES 'OTHER_CODE_SIGN_FLAGS=--timestamp=none' build
codesign --verify --deep --strict .build/signed-xcode/Build/Products/Release/CameraBar.app
```

Quit the ad hoc viewer, open `.build/signed-xcode/Build/Products/Release/CameraBar.app`, and add **Camera Bar** through macOS's **Edit Widgets**. Select a camera and keep the app running. Build-setting overrides leave the default ad hoc project configuration intact; persist signing settings in `project.yml` if desired, since bootstrap regenerates the Xcode project.

This command creates a local build without a secure timestamp or notarization. Before distributing outside your Mac, use secure timestamping, notarize the app, and verify the widget in the desktop gallery. On 2026-11-06, Developer ID signing and real sandboxed/unsandboxed App Group file sharing passed for team `79867GLCBR`; gallery rendering and existing camera credential access under the new signature remain unverified because desktop control could not start. The temporary signing keychain was removed after the build.

## Verification

Install `ffmpeg` and `mediamtx` for the real RTSP fixture:

```sh
brew install ffmpeg mediamtx
scripts/check
```

Checks cover core tests, Swift formatting, native Keychain/file tests, actual RTSP decoding and image pixels, camera cancellation, background playback lifetime, and the actual UI camera lifecycle. Native tests use disposable Keychain IDs and files. UI tests add uniquely named local cameras through the ordinary settings UI, remove their own records even after failures, and restore the prior camera selection and running state. Run UI tests on a logged-in macOS desktop with Accessibility permission for Xcode's test runner; they must not run against a session where changing the selected camera would interrupt your work.

`scripts/test-rtsp --serve` runs just the local fixture at `rtsp://127.0.0.1:18554/live`. Stop it with Ctrl-C. `scripts/test-rtsp --ui` runs UI tests against that fixture. Scripts refuse an occupied port and terminate only processes they started. Logs and XCTest attachments live in `.build/`.

On the development Mac, Xcode reports mismatched CoreDevice/CoreSimulator components, an AppIntents metadata notice, and system service diagnostics from `linkd` and `DetachedSignatures`. These are retained in the full logs. Update the Xcode platform components to resolve the host installation messages. VLCKit also reports that its snapshot color conversion uses the CPU; the integration tests verify the resulting image pixels. These diagnostics are separate from compiler errors and test failures.

A fresh Release build also reports warnings in VLCKit's bundled headers about framework include quoting and documentation. The signed Release build succeeded with those vendor warnings; they remain in `.build/signing-work/build.log` for the local signing run.

## Dependency license

VLCKit 3.7.3 is dynamically linked and distributed under LGPL 2.1 or later; its bundled license is in `THIRD_PARTY_NOTICES.txt`. Source and build instructions are available from [VideoLAN VLCKit](https://code.videolan.org/videolan/VLCKit) and [VLC](https://code.videolan.org/videolan/vlc). The pinned binary archive is `VLCKit-3.7.3-319ed2c0-79128878.tar.xz`, SHA-256 `019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d`. Preserve the license and applicable source/relinking obligations when distributing a signed app; this repository currently supplies local development builds.
