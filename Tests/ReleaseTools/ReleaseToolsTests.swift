// ABOUTME: Tests release inputs and real temporary-keychain lifecycle behavior.
// ABOUTME: Uses disposable local keychains without signing credentials or mocked commands.
import Foundation
import Security

@available(macOS, deprecated: 10.10, message: "Exercises the legacy file-keychain adapter")
@main
struct ReleaseToolsTests {
  static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ReleaseFailure(message: message) }
  }

  static func main() throws {
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
    print("Release argument, credential, and real keychain cleanup tests passed")
  }
}
