// ABOUTME: Resolves the shared snapshot container and validates widget image data.
// ABOUTME: Keeps the widget independent of camera credentials and playback.
import AppKit
import CameraBarCore
import Foundation
import Security

struct WidgetSnapshot {
  let image: NSImage
  let cameraName: String
  let capturedAt: Date

  static func load(from store: SnapshotStore) -> WidgetSnapshot? {
    guard let snapshot = try? store.read(), let image = NSImage(data: snapshot.jpegData) else {
      return nil
    }
    return WidgetSnapshot(
      image: image, cameraName: snapshot.cameraName, capturedAt: snapshot.capturedAt)
  }
}

enum SharedContainer {
  static func hasSignedGroupAccess(_ group: String) -> Bool {
    var code: SecCode?
    var staticCode: SecStaticCode?
    var information: CFDictionary?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
      SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
      SecCodeCopySigningInformation(
        staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
      let values = information as? [String: Any],
      let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty,
      let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
      let groups = entitlements["com.apple.security.application-groups"] as? [String]
    else { return false }
    return groups.contains(group)
  }

  static func snapshotStore() -> SnapshotStore? {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "CameraBarAppGroup") as? String,
      hasSignedGroupAccess(group),
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return nil }
    return SnapshotStore(fileURL: container.appendingPathComponent("latest-snapshot.json"))
  }
}
