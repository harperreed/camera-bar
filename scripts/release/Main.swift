// ABOUTME: Builds, notarizes, and packages the universal Developer ID release.
// ABOUTME: Writes only the stapled ZIP and checksum to the release artifact directory.
import CryptoKit
import Foundation
import Security

@available(macOS, deprecated: 10.10, message: "Uses the file-keychain adapter required by codesign")
@main
struct ReleaseMain {
  static func main() {
    do { try release() } catch {
      fputs("Release failed: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }

  static func release() throws {
    let options = try ReleaseOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    let credentials = try ReleaseCredentials(environment: ProcessInfo.processInfo.environment)
    let secret = credentials.values
    let root = FileManager.default.currentDirectoryPath
    try run(root + "/scripts/bootstrap", [], log: ".build/release-bootstrap.log")
    let app = root + "/.build/release-xcode/Build/Products/Release/CameraBar.app"
    try SigningKeychain.withTemporary { keychain, path in
      try SigningKeychain.importIdentity(credentials, into: keychain)
      try run(
        "/usr/bin/xcodebuild",
        [
          "-project", "CameraBar.xcodeproj", "-scheme", "CameraBar", "-configuration", "Release",
          "-destination", "generic/platform=macOS", "-derivedDataPath", ".build/release-xcode",
          "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "CODE_SIGNING_ALLOWED=YES",
          "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=\(secret["APPLE_TEAM_ID"]!)",
          "CODE_SIGN_IDENTITY=\(secret["APPLE_SIGNING_IDENTITY"]!)",
          "CAMERA_BAR_APP_GROUP=\(secret["APPLE_TEAM_ID"]!).com.harper.camera-bar",
          "OTHER_CODE_SIGN_FLAGS=--keychain \(path) --timestamp", "ENABLE_HARDENED_RUNTIME=YES",
          "MARKETING_VERSION=\(options.version)", "CURRENT_PROJECT_VERSION=\(options.build)",
          "build",
        ], log: ".build/release-build.log")
    }
    try run(
      "/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", app],
      log: ".build/release-signature.log")
    for (name, bundle, executable) in [
      ("app", app, "Contents/MacOS/CameraBar"),
      ("widget", app + "/Contents/PlugIns/CameraBarWidget.appex", "Contents/MacOS/CameraBarWidget"),
    ] {
      let info =
        try PropertyListSerialization.propertyList(
          from: Data(contentsOf: URL(fileURLWithPath: bundle + "/Contents/Info.plist")), format: nil
        ) as? [String: Any]
      guard info?["CFBundleShortVersionString"] as? String == options.version,
        info?["CFBundleVersion"] as? String == options.build
      else { throw ReleaseFailure(message: "\(name) bundle version does not match the release") }
      try run(
        "/usr/bin/lipo", [bundle + "/" + executable, "-verify_arch", "arm64", "x86_64"],
        log: ".build/release-\(name)-architectures.log")
      try run(
        "/usr/bin/codesign", ["--display", "--verbose=4", bundle],
        log: ".build/release-\(name)-signature.log")
      let signature = try String(
        contentsOfFile: ".build/release-\(name)-signature.log", encoding: .utf8)
      guard signature.contains("TeamIdentifier=\(secret["APPLE_TEAM_ID"]!)"),
        signature.contains("runtime"), signature.contains("Timestamp=")
      else {
        throw ReleaseFailure(
          message: "\(name) lacks the expected team, hardened runtime, or secure timestamp")
      }
    }
    try run(
      "/usr/bin/lipo",
      [app + "/Contents/Frameworks/VLCKit.framework/VLCKit", "-verify_arch", "arm64", "x86_64"],
      log: ".build/release-vlc-architectures.log")
    print(
      "Verified Developer ID signatures, secure timestamps, hardened runtime, matching versions, and arm64/x86_64 app, widget, and VLC."
    )

    try withTemporaryDirectory(prefix: "camera-bar-notary-") { temporary in
      let key = temporary.appendingPathComponent("AuthKey.p8")
      guard
        FileManager.default.createFile(
          atPath: key.path, contents: Data(secret["APPLE_API_PRIVATE_KEY"]!.utf8),
          attributes: [.posixPermissions: 0o600])
      else {
        throw ReleaseFailure(message: "Cannot create temporary notarization key")
      }
      let authentication = [
        "--key", key.path, "--key-id", secret["APPLE_API_KEY_ID"]!, "--issuer",
        secret["APPLE_API_ISSUER_ID"]!,
      ]
      let submission = temporary.appendingPathComponent("CameraBar.zip").path
      try run(
        "/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app, submission],
        log: ".build/release-package.log")
      let submissionResult = Result {
        try run(
          "/usr/bin/xcrun",
          ["notarytool", "submit", submission] + authentication + [
            "--wait", "--timeout", "20m", "--output-format", "json",
          ], log: ".build/release-notary.log", errorLog: ".build/release-notary-errors.log")
      }
      let response = try? JSONDecoder().decode(
        NotaryResponse.self,
        from: Data(contentsOf: URL(fileURLWithPath: ".build/release-notary.log"))
      )
      if let id = response?.id {
        try run(
          "/usr/bin/xcrun", ["notarytool", "log", id] + authentication,
          log: ".build/release-notary-details.log")
      }
      try submissionResult.get()
      guard response?.accepted == true else {
        throw ReleaseFailure(
          message:
            "Apple did not accept the submission. See .build/release-notary.log and .build/release-notary-details.log"
        )
      }
    }
    try run("/usr/bin/xcrun", ["stapler", "staple", app], log: ".build/release-staple.log")
    try run(
      "/usr/bin/xcrun", ["stapler", "validate", app], log: ".build/release-staple-validation.log")
    try run(
      "/usr/bin/codesign", ["--verify", "--deep", "--strict", app],
      log: ".build/release-final-signature.log")
    try run(
      "/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=2", app],
      log: ".build/release-gatekeeper.log")
    let output = root + "/.build/release"
    try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
    let name = "CameraBar-\(options.version).zip"
    let zip = output + "/" + name
    guard !FileManager.default.fileExists(atPath: zip) else {
      throw ReleaseFailure(
        message: "Release ZIP already exists: \(zip). Move the previous artifact before retrying.")
    }
    try run(
      "/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app, zip],
      log: ".build/release-final-package.log")
    let digest = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: zip))).map {
      String(format: "%02x", $0)
    }.joined()
    try "\(digest)  \(name)\n".write(toFile: zip + ".sha256", atomically: true, encoding: .utf8)
    print("Notarized release ready: \(zip)")
  }
}
