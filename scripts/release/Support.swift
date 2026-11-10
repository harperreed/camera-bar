// ABOUTME: Validates release inputs and manages the temporary signing keychain.
// ABOUTME: Keeps credentials out of child environments and process arguments.
import Foundation
import Security

struct ReleaseFailure: Error, LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

struct ReleaseOptions {
  let version: String
  let build: String
  init(arguments: [String]) throws {
    guard arguments.count == 2,
      arguments[0].range(
        of: #"\Av(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z"#, options: .regularExpression)
        != nil,
      arguments[1].range(of: #"\A[1-9][0-9]*\z"#, options: .regularExpression) != nil
    else {
      throw ReleaseFailure(message: "Usage: scripts/release-build vMAJOR.MINOR.PATCH BUILD_NUMBER")
    }
    version = String(arguments[0].dropFirst())
    build = arguments[1]
  }
}

struct ReleaseCredentials {
  static let names = [
    "APPLE_CERTIFICATE_P12_BASE64", "APPLE_CERTIFICATE_PASSWORD", "APPLE_SIGNING_IDENTITY",
    "APPLE_TEAM_ID", "APPLE_API_KEY_ID", "APPLE_API_ISSUER_ID", "APPLE_API_PRIVATE_KEY",
    "SPARKLE_PRIVATE_KEY",
  ]
  let values: [String: String]
  init(environment: [String: String]) throws {
    values = environment.filter { Self.names.contains($0.key) }.mapValues {
      $0.trimmingCharacters(in: .newlines)
    }
    for name in Self.names {
      guard let value = values[name], !value.isEmpty else {
        throw ReleaseFailure(message: "Missing required secret: \(name)")
      }
    }
  }
}

// File keychains are deprecated by Apple but remain required for an isolated codesign identity.
@available(macOS, deprecated: 10.10, message: "Uses the file-keychain API required by codesign")
enum SigningKeychain {
  static func check(_ status: OSStatus, _ operation: String) throws {
    guard status == errSecSuccess else {
      throw ReleaseFailure(message: "\(operation) failed (Security status \(status))")
    }
  }

  static func withTemporary<T>(_ body: (SecKeychain, String) throws -> T) throws -> T {
    var previous: CFArray?
    try check(SecKeychainCopySearchList(&previous), "Read keychain search list")
    guard let previous else { throw ReleaseFailure(message: "Missing keychain search list") }
    return try withTemporaryDirectory(prefix: "camera-bar-signing-") { directory in
      let path = directory.appendingPathComponent("signing.keychain-db").path
      let password = Data((UUID().uuidString + UUID().uuidString).utf8)
      var created: SecKeychain?
      try password.withUnsafeBytes { bytes in
        try check(
          SecKeychainCreate(path, UInt32(password.count), bytes.baseAddress, false, nil, &created),
          "Create signing keychain")
      }
      guard let keychain = created else {
        throw ReleaseFailure(message: "Missing created keychain")
      }
      let result = Result {
        try check(
          SecKeychainSetSearchList(([keychain] + (previous as! [SecKeychain])) as CFArray),
          "Set signing search list")
        return try body(keychain, path)
      }
      let restoration = SecKeychainSetSearchList(previous)
      let deletion = SecKeychainDelete(keychain)
      try check(restoration, "Restore keychain search list")
      try check(deletion, "Delete signing keychain")
      return try result.get()
    }
  }
}

func childEnvironment(_ environment: [String: String]) -> [String: String] {
  environment.filter {
    !$0.key.hasPrefix("APPLE_")
      && !["GH_TOKEN", "GITHUB_TOKEN", "SPARKLE_PRIVATE_KEY"].contains($0.key)
  }
}

func run(_ executable: String, _ arguments: [String], log: String, errorLog: String? = nil) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.environment = childEnvironment(ProcessInfo.processInfo.environment)
  FileManager.default.createFile(atPath: log, contents: nil)
  let output = try FileHandle(forWritingTo: URL(fileURLWithPath: log))
  defer { try? output.close() }
  process.standardOutput = output
  var diagnostics: FileHandle?
  if let errorLog {
    FileManager.default.createFile(atPath: errorLog, contents: nil)
    diagnostics = try FileHandle(forWritingTo: URL(fileURLWithPath: errorLog))
  }
  defer { try? diagnostics?.close() }
  process.standardError = diagnostics ?? output
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    for path in [log, errorLog].compactMap({ $0 }) {
      if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        fputs(content.split(separator: "\n").suffix(40).joined(separator: "\n") + "\n", stderr)
      }
    }
    throw ReleaseFailure(
      message:
        "\(URL(fileURLWithPath: executable).lastPathComponent) failed (\(process.terminationStatus)). Full log: \(log)"
    )
  }
}

@available(macOS, deprecated: 10.10, message: "Uses the file-keychain API required by codesign")
extension SigningKeychain {
  static func importIdentity(_ credentials: ReleaseCredentials, into keychain: SecKeychain) throws {
    var trusted: SecTrustedApplication?
    try check(
      SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &trusted), "Authorize codesign")
    guard let trusted else { throw ReleaseFailure(message: "Missing trusted codesign application") }
    var access: SecAccess?
    try check(
      SecAccessCreate("Camera Bar release signing" as CFString, [trusted] as CFArray, &access),
      "Create signing access")
    guard let access else { throw ReleaseFailure(message: "Missing signing access") }
    let passphrase = credentials.values["APPLE_CERTIFICATE_PASSWORD"]! as CFString
    let attributes = [kSecAttrIsPermanent, kSecAttrIsSensitive] as CFArray
    let usage = [kSecAttrCanSign] as CFArray
    var parameters = SecItemImportExportKeyParameters()
    parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
    parameters.passphrase = Unmanaged.passUnretained(passphrase)
    parameters.accessRef = Unmanaged.passUnretained(access)
    parameters.keyAttributes = Unmanaged.passUnretained(attributes)
    parameters.keyUsage = Unmanaged.passUnretained(usage)
    var format = SecExternalFormat.formatPKCS12
    var type = SecExternalItemType.itemTypeAggregate
    let encoded = credentials.values["APPLE_CERTIFICATE_P12_BASE64"]!.filter { !$0.isWhitespace }
    guard let archive = Data(base64Encoded: encoded) else {
      throw ReleaseFailure(message: "APPLE_CERTIFICATE_P12_BASE64 is not valid base64")
    }
    try check(
      SecItemImport(archive as CFData, nil, &format, &type, [], &parameters, keychain, nil),
      "Import signing identity")
  }
}

struct NotaryResponse: Decodable {
  let id: String?
  let status: String
  var accepted: Bool { status == "Accepted" }
}

func withTemporaryDirectory<T>(prefix: String, _ body: (URL) throws -> T) throws -> T {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    prefix + UUID().uuidString)
  try FileManager.default.createDirectory(
    at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
  let result = Result { try body(directory) }
  do {
    try FileManager.default.removeItem(at: directory)
  } catch {
    throw ReleaseFailure(
      message:
        "Cannot remove temporary credentials directory \(directory.path): \(error.localizedDescription)"
    )
  }
  return try result.get()
}

func verifyUniversalBinary(_ path: String, logPrefix: String) throws {
  for architecture in ["arm64", "x86_64"] {
    try run(
      "/usr/bin/lipo", [path, "-verify_arch", architecture],
      log: logPrefix + "-" + architecture + ".log")
  }
}

func validateReleaseEntitlements(_ data: Data, appGroup: String) throws {
  guard
    let entitlements = try PropertyListSerialization.propertyList(from: data, format: nil)
      as? [String: Any]
  else {
    throw ReleaseFailure(message: "Release entitlements must be a property-list dictionary")
  }
  guard entitlements["com.apple.security.get-task-allow"] == nil else {
    throw ReleaseFailure(message: "Release signature must omit com.apple.security.get-task-allow")
  }
  guard entitlements["com.apple.security.application-groups"] as? [String] == [appGroup] else {
    throw ReleaseFailure(message: "Release signature has an unexpected App Group")
  }
}

func verifyReleaseEntitlements(_ bundle: String, appGroup: String, logPrefix: String) throws {
  for architecture in ["arm64", "x86_64"] {
    let log = logPrefix + "-" + architecture + ".log"
    try run(
      "/usr/bin/codesign",
      ["--display", "--arch", architecture, "--entitlements", "-", "--xml", bundle], log: log,
      errorLog: logPrefix + "-" + architecture + "-diagnostics.log")
    try validateReleaseEntitlements(Data(contentsOf: URL(fileURLWithPath: log)), appGroup: appGroup)
  }
}

func signSparkleFramework(_ framework: String, identity: String, keychain: String?, log: String)
  throws
{
  var arguments = ["--force", "--sign", identity, "--options", "runtime"]
  if let keychain { arguments += ["--keychain", keychain, "--timestamp"] }
  for (index, component) in [
    "/Versions/B/XPCServices/Installer.xpc", "/Versions/B/XPCServices/Downloader.xpc",
    "/Versions/B/Autoupdate", "/Versions/B/Updater.app", "",
  ].enumerated() {
    let entitlements =
      component.hasSuffix("Downloader.xpc") ? ["--preserve-metadata=entitlements"] : []
    try run(
      "/usr/bin/codesign", arguments + entitlements + [framework + component],
      log: "\(log)-\(index).log")
  }
}

func generateSignedAppcast(archives: String, version: String, privateKey: String, logPrefix: String)
  throws
{
  try withTemporaryDirectory(prefix: "camera-bar-update-key-") { directory in
    let key = directory.appendingPathComponent("ed25519")
    guard
      FileManager.default.createFile(
        atPath: key.path, contents: Data(privateKey.utf8),
        attributes: [.posixPermissions: 0o600])
    else {
      throw ReleaseFailure(message: "Cannot create temporary update signing key")
    }
    let tools = URL(fileURLWithPath: "Vendor/Sparkle/bin").standardizedFileURL
    try run(
      tools.appendingPathComponent("generate_appcast").path,
      [
        "--ed-key-file", key.path, "--maximum-deltas", "0", "--maximum-versions", "1",
        "--download-url-prefix",
        "https://github.com/harperreed/camera-bar/releases/download/v\(version)/",
        archives,
      ], log: logPrefix + "-generate.log")
    try run(
      tools.appendingPathComponent("sign_update").path,
      [
        "--verify", "--ed-key-file", key.path, archives + "/appcast.xml",
      ], log: logPrefix + "-verify.log")
  }
}
