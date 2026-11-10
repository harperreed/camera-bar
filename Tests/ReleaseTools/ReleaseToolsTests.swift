// ABOUTME: Tests release inputs and real temporary-keychain lifecycle behavior.
// ABOUTME: Uses disposable local keychains without signing credentials or mocked commands.
import CryptoKit
import Foundation
import Security

@available(macOS, deprecated: 10.10, message: "Exercises the legacy file-keychain adapter")
@main
struct ReleaseToolsTests {
  static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ReleaseFailure(message: message) }
  }

  static func main() throws {
    if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--verify-binary" {
      do {
        try verifyUniversalBinary(CommandLine.arguments[2], logPrefix: CommandLine.arguments[3])
      } catch {
        fputs(error.localizedDescription + "\n", stderr)
        exit(1)
      }
      return
    }
    try testUniversalBinaries()
    try testReleaseEntitlements()
    try testUpdateConfiguration()
    try testSignedUpdates()
    let options = try ReleaseOptions(arguments: ["v12.3.4", "75"])
    try require(options.version == "12.3.4" && options.build == "75", "Version or build differs")
    for args in [
      [], ["v1.0.0"], ["1.0.0", "1"], ["v01.0.0", "1"], ["v1.0.0-rc1", "1"],
      ["v1.0.0\n", "1"], ["v1.0.0;echo nope", "1"], ["v1.0.0", "0"], ["v1.0.0", "-1"],
      ["v1.0.0", "1", "extra"],
    ] {
      do {
        _ = try ReleaseOptions(arguments: args)
        throw ReleaseFailure(message: "Accepted invalid release arguments: \(args)")
      } catch let error as ReleaseFailure {
        try require(!error.message.hasPrefix("Accepted"), error.message)
      }
    }
    do {
      _ = try ReleaseCredentials(environment: [:])
      throw ReleaseFailure(message: "Accepted missing credentials")
    } catch let error as ReleaseFailure {
      try require(
        error.message.contains("Missing required secret: APPLE_CERTIFICATE_P12_BASE64"),
        "Missing-secret error lacks the variable name")
    }
    var environment = Dictionary(
      uniqueKeysWithValues: ReleaseCredentials.names.map { ($0, "value\n") })
    let trimmed = try ReleaseCredentials(environment: environment)
    try require(
      trimmed.values.values.allSatisfy { $0 == "value" },
      "Secret-file line endings were not removed")
    environment["APPLE_TEAM_ID"] = "\n"
    do {
      _ = try ReleaseCredentials(environment: environment)
      throw ReleaseFailure(message: "Accepted a blank secret file")
    } catch let error as ReleaseFailure {
      try require(error.message == "Missing required secret: APPLE_TEAM_ID", error.message)
    }
    let child = childEnvironment([
      "PATH": "/usr/bin", "APPLE_CERTIFICATE_PASSWORD": "sensitive", "GH_TOKEN": "token",
      "GITHUB_TOKEN": "token",
      "SPARKLE_PRIVATE_KEY": "sensitive",
    ])
    try require(child == ["PATH": "/usr/bin"], "Child process inherited secrets")
    for status in ["Accepted", "Invalid", "Rejected", "In Progress"] {
      let response = try JSONDecoder().decode(
        NotaryResponse.self, from: Data("{\"id\":\"submission-id\",\"status\":\"\(status)\"}".utf8))
      try require(response.id == "submission-id", "Lost notarization submission ID")
      try require(
        response.accepted == (status == "Accepted"), "Accepted an unsuccessful notarization")
    }
    var protectedDirectory: URL?
    defer {
      if let protectedDirectory {
        try? FileManager.default.setAttributes(
          [.posixPermissions: 0o700],
          ofItemAtPath: protectedDirectory.appendingPathComponent("locked").path)
        try? FileManager.default.removeItem(at: protectedDirectory)
      }
    }
    var cleanupFailed = false
    do {
      try withTemporaryDirectory(prefix: "camera-bar-cleanup-test-") { directory in
        protectedDirectory = directory
        let locked = directory.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try Data("test".utf8).write(to: locked.appendingPathComponent("fixture"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
      }
    } catch let error as ReleaseFailure {
      try require(
        error.message.hasPrefix("Cannot remove temporary credentials directory"), error.message)
      cleanupFailed = true
    }
    try require(cleanupFailed, "Temporary directory cleanup failure was ignored")
    var before: CFArray?
    try require(
      SecKeychainCopySearchList(&before) == errSecSuccess, "Cannot read initial keychains")
    for fail in [false, true] {
      var path = ""
      do {
        try SigningKeychain.withTemporary { keychain, keychainPath in
          path = keychainPath
          try require(
            FileManager.default.fileExists(atPath: path), "Temporary keychain was not created")
          var during: CFArray?
          try require(
            SecKeychainCopySearchList(&during) == errSecSuccess, "Cannot read active keychains")
          try require(
            (during as! [SecKeychain]).contains(keychain), "Signing keychain is not searchable")
          if fail { throw ReleaseFailure(message: "Deliberate body failure") }
        }
        try require(!fail, "Expected body failure")
      } catch let error as ReleaseFailure {
        try require(fail && error.message == "Deliberate body failure", error.message)
      }
      try require(
        !path.isEmpty && !FileManager.default.fileExists(atPath: path), "Temporary keychain leaked")
      try require(
        !FileManager.default.fileExists(
          atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path),
        "Temporary directory leaked")
      var after: CFArray?
      try require(
        SecKeychainCopySearchList(&after) == errSecSuccess, "Cannot read restored keychains")
      try require(CFEqual(before, after), "Keychain search list was not restored")
    }
    print(
      "Release inputs, secret isolation, keychain cleanup, and real Sparkle signature tests passed")
  }
  static func testUniversalBinaries() throws {
    try withTemporaryDirectory(prefix: "camera-bar-architectures-test-") { directory in
      let source = directory.appendingPathComponent("fixture.c").path
      try "int fixture(void) { return 42; }\n".write(
        toFile: source, atomically: true, encoding: .utf8)
      let architectures = ["arm64", "x86_64"]
      for architecture in architectures {
        try run(
          "/usr/bin/clang",
          [
            "-arch", architecture, "-c", source, "-o",
            directory.appendingPathComponent(architecture + ".o").path,
          ], log: directory.appendingPathComponent(architecture + "-compile.log").path)
      }
      let universal = directory.appendingPathComponent("universal.o").path
      try run(
        "/usr/bin/lipo",
        [
          "-create", directory.appendingPathComponent("arm64.o").path,
          directory.appendingPathComponent("x86_64.o").path, "-output", universal,
        ], log: directory.appendingPathComponent("combine.log").path)
      try verifyUniversalBinary(
        universal, logPrefix: directory.appendingPathComponent("universal-verification").path)
      for architecture in architectures {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [
          "--verify-binary", directory.appendingPathComponent(architecture + ".o").path,
          directory.appendingPathComponent(architecture + "-verification").path,
        ]
        process.environment = childEnvironment(ProcessInfo.processInfo.environment)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let diagnostics = String(
          decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        try require(
          process.terminationStatus != 0, "Accepted a thin \(architecture) Mach-O as universal")
        try require(
          diagnostics.contains("lipo failed"),
          "Thin binary did not fail architecture verification: \(diagnostics)")
      }
    }
  }

  static func testUpdateConfiguration() throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: "CameraBar/Info.plist"))
    let info = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    try require(
      info["SUFeedURL"] as? String
        == "https://github.com/harperreed/camera-bar/releases/latest/download/appcast.xml",
      "The app has no public update feed")
    try require(
      info["SUPublicEDKey"] as? String == "PaSB4NO6pnCukyyNPnwMp6fWp9rXVQCJXzT4H/hoRh4=",
      "The app does not trust the release signing key")
    try require(
      info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
      "Archives must verify before extraction")
    try require(
      info["SURequireSignedFeed"] as? Bool == true, "Update feeds must require a signature")
    try require(
      info["SUSignedFeedFailureExpirationInterval"] as? Int == 0,
      "Signed-feed enforcement must not expire after verification failures")
    try require(
      info["SUEnableAutomaticChecks"] == nil, "Preserve Sparkle's automatic-check consent")
  }

  static func testSignedUpdates() throws {
    try withTemporaryDirectory(prefix: "camera-bar-update-test-") { directory in
      let key = Curve25519.Signing.PrivateKey()
      let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
      let app = directory.appendingPathComponent("Fixture.app")
      let contents = app.appendingPathComponent("Contents")
      try FileManager.default.createDirectory(
        at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
      try FileManager.default.createDirectory(
        at: contents.appendingPathComponent("Frameworks"), withIntermediateDirectories: true)
      let info: [String: Any] = [
        "CFBundleIdentifier": "com.harper.camera-bar.update-test.\(UUID().uuidString)",
        "CFBundleName": "Update Fixture", "CFBundleExecutable": "Fixture",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "42", "CFBundleShortVersionString": "1.1.0",
        "LSMinimumSystemVersion": "14.0",
        "SUPublicEDKey": publicKey, "SURequireSignedFeed": true,
        "SUSignedFeedFailureExpirationInterval": 0,
        "SUVerifyUpdateBeforeExtraction": true,
        "SUFeedURL": "https://example.com/appcast.xml",
      ]
      try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
      let source = directory.appendingPathComponent("fixture.c")
      try "int main(void) { return 0; }\n".write(to: source, atomically: true, encoding: .utf8)
      try run(
        "/usr/bin/clang",
        [source.path, "-o", contents.appendingPathComponent("MacOS/Fixture").path],
        log: directory.appendingPathComponent("compile.log").path)
      let framework = contents.appendingPathComponent("Frameworks/Sparkle.framework")
      try FileManager.default.copyItem(
        at: URL(fileURLWithPath: "Vendor/Sparkle/Sparkle.framework"), to: framework)
      // Xcode removes headers/modules while embedding frameworks; reproduce that changed resource seal.
      for name in ["Headers", "Modules"] {
        let path = framework.appendingPathComponent("Versions/B/\(name)")
        if FileManager.default.fileExists(atPath: path.path) {
          try FileManager.default.removeItem(at: path)
        }
        let link = framework.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: link)
      }
      try signSparkleFramework(
        framework.path, identity: "-", keychain: nil,
        log: directory.appendingPathComponent("sign-sparkle").path)
      try run(
        "/usr/bin/codesign", ["--force", "--sign", "-", app.path],
        log: directory.appendingPathComponent("sign.log").path)
      try run(
        "/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path],
        log: directory.appendingPathComponent("verify.log").path)
      let archives = directory.appendingPathComponent("archives")
      try FileManager.default.createDirectory(at: archives, withIntermediateDirectories: false)
      let zip = archives.appendingPathComponent("CameraBar-1.1.0.zip")
      try run(
        "/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path],
        log: directory.appendingPathComponent("zip.log").path)
      try generateSignedAppcast(
        archives: archives.path, version: "1.1.0",
        privateKey: key.rawRepresentation.base64EncodedString(),
        logPrefix: directory.appendingPathComponent("appcast").path)
      let feed = archives.appendingPathComponent("appcast.xml")
      let xml = try XMLDocument(contentsOf: feed)
      let enclosure = try xml.nodes(forXPath: "/rss/channel/item/enclosure").first as! XMLElement
      try require(
        enclosure.attribute(forName: "url")?.stringValue
          == "https://github.com/harperreed/camera-bar/releases/download/v1.1.0/CameraBar-1.1.0.zip",
        "Update URL is not immutable")
      let signature = Data(
        base64Encoded: enclosure.attribute(forName: "sparkle:edSignature")!.stringValue!)!
      let archive = try Data(contentsOf: zip)
      try require(
        key.publicKey.isValidSignature(signature, for: archive), "Archive signature is invalid")
      try require(
        !key.publicKey.isValidSignature(signature, for: archive + Data([0])),
        "Tampered archive accepted")
      try require(
        (try xml.nodes(forXPath: "/rss/channel/item/sparkle:version")).first?.stringValue == "42",
        "Feed lost the build number")
      try require(
        (try xml.nodes(forXPath: "/rss/channel/item/sparkle:shortVersionString")).first?.stringValue
          == "1.1.0", "Feed lost the marketing version")
      try require((try xml.nodes(forXPath: "//sparkle:deltas")).isEmpty, "Unexpected delta update")
      // Verify the embedded feed signature with Sparkle's own verifier, including rejection after mutation.
      let keyFile = directory.appendingPathComponent("test-key")
      FileManager.default.createFile(
        atPath: keyFile.path,
        contents: Data(key.rawRepresentation.base64EncodedString().utf8),
        attributes: [.posixPermissions: 0o600])
      let verifier = URL(fileURLWithPath: "Vendor/Sparkle/bin/sign_update").standardizedFileURL
      try run(
        verifier.path, ["--verify", "--ed-key-file", keyFile.path, feed.path],
        log: directory.appendingPathComponent("feed-verification.log").path)
      let originalFeed = try String(contentsOf: feed, encoding: .utf8)
      let mutated = originalFeed.replacingOccurrences(
        of: "CameraBar-1.1.0.zip", with: "CameraBar-9.9.9.zip")
      try require(mutated != originalFeed, "Feed mutation did not change the download URL")
      try mutated.write(to: feed, atomically: true, encoding: .utf8)
      let process = Process()
      process.executableURL = verifier
      process.arguments = ["--verify", "--ed-key-file", keyFile.path, feed.path]
      process.environment = childEnvironment(ProcessInfo.processInfo.environment)
      let output = Pipe()
      process.standardOutput = output
      process.standardError = output
      try process.run()
      let diagnostic = String(
        decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      process.waitUntilExit()
      try require(process.terminationStatus != 0, "Tampered appcast accepted")
      try require(
        diagnostic.contains("failed to pass signing verification"),
        "Feed verifier diagnostic: \(diagnostic)")
    }
  }

  static func testReleaseEntitlements() throws {
    let group = "TESTTEAM.com.harper.camera-bar"
    let valid = ["com.apple.security.application-groups": [group]]
    try validateReleaseEntitlements(
      PropertyListSerialization.data(fromPropertyList: valid, format: .xml, options: 0),
      appGroup: group)
    let invalid: [[String: Any]] = [
      [
        "com.apple.security.application-groups": [group], "com.apple.security.get-task-allow": true,
      ],
      [
        "com.apple.security.application-groups": [group],
        "com.apple.security.get-task-allow": false,
      ],
      ["com.apple.security.application-groups": ["OTHERTEAM.com.harper.camera-bar"]],
      ["com.apple.security.application-groups": [group, "another-group"]],
      ["com.apple.security.application-groups": group],
      [:],
    ]
    for entitlements in invalid {
      let data = try PropertyListSerialization.data(
        fromPropertyList: entitlements, format: .xml, options: 0)
      var rejected = false
      do { try validateReleaseEntitlements(data, appGroup: group) } catch { rejected = true }
      try require(
        rejected, "Accepted distribution entitlements with debugger access or incorrect groups")
    }
    var rejectedMalformed = false
    do { try validateReleaseEntitlements(Data("not a plist".utf8), appGroup: group) } catch {
      rejectedMalformed = true
    }
    try require(rejectedMalformed, "Accepted malformed entitlement data")
  }

}
