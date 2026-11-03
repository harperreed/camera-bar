// ABOUTME: Exercises credentials and camera state against real Keychain and files.
// ABOUTME: Uses disposable identifiers so tests never touch saved user cameras.
import AppKit
import CameraBarCore
import XCTest

@MainActor
final class ServiceTests: XCTestCase {
  func testKeychainRoundTripAndDeletion() throws {
    let store = CredentialStore(service: "CameraBarTests.\(UUID())")
    let id = UUID()
    defer { try? store.remove(id: id) }
    XCTAssertNil(try store.read(id: id))
    try store.write(
      try RTSPAddress("rtsp://name:secret@localhost:18554/live?token=private"), id: id)
    XCTAssertEqual(
      try store.read(id: id)?.rawValue, "rtsp://name:secret@localhost:18554/live?token=private")
    try store.write(try RTSPAddress("rtsp://localhost:18554/other"), id: id)
    XCTAssertEqual(try store.read(id: id)?.rawValue, "rtsp://localhost:18554/other")
    try store.remove(id: id)
    XCTAssertNil(try store.read(id: id))
  }

  func testSelectionClearsSnapshotAndRejectsOldCapture() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let catalog = try CameraCatalog(fileURL: folder.appendingPathComponent("cameras.json"))
    let credentials = CredentialStore(service: "CameraBarTests.\(UUID())")
    let snapshots = SnapshotStore(fileURL: folder.appendingPathComponent("snapshot.json"))
    let model = CameraState(catalog: catalog, credentials: credentials, snapshots: snapshots)
    let first = try model.add(name: "One", address: "rtsp://localhost:18554/live")
    let second = try model.add(name: "Two", address: "rtsp://localhost:18554/other")
    defer {
      try? credentials.remove(id: first.id)
      try? credentials.remove(id: second.id)
    }
    let generation = model.generation
    try model.publish(
      jpegData: Data([1]), capturedAt: Date(timeIntervalSince1970: 10), generation: generation)
    XCTAssertNotNil(try snapshots.read())
    try model.select(id: second.id)
    XCTAssertNil(try snapshots.read())
    try model.publish(jpegData: Data([2]), capturedAt: Date(), generation: generation)
    XCTAssertNil(try snapshots.read())
    XCTAssertEqual(model.selectedCamera?.id, second.id)
    try model.remove(id: second.id)
    XCTAssertEqual(model.selectedCamera?.id, first.id)
    XCTAssertNil(try credentials.read(id: second.id))
  }

  func testFailedCatalogEditRestoresCredential() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("catalog.json")
    let credentials = CredentialStore(service: "CameraBarTests.\(UUID())")
    let model = CameraState(
      catalog: try CameraCatalog(fileURL: file), credentials: credentials, snapshots: nil)
    let camera = try model.add(name: "One", address: "rtsp://localhost/original")
    defer { try? credentials.remove(id: camera.id) }
    try FileManager.default.removeItem(at: folder)
    try Data().write(to: folder)
    XCTAssertThrowsError(
      try model.edit(id: camera.id, name: "Changed", address: "rtsp://localhost/changed"))
    XCTAssertEqual(try credentials.read(id: camera.id)?.rawValue, "rtsp://localhost/original")
    XCTAssertEqual(model.selectedCamera?.name, "One")
  }

  func testSnapshotClearFailureDoesNotCommitEdit() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let snapshotsURL = folder.appendingPathComponent("snapshot.json")
    let credentials = CredentialStore(service: "CameraBarTests.\(UUID())")
    let model = CameraState(
      catalog: try CameraCatalog(fileURL: folder.appendingPathComponent("catalog.json")),
      credentials: credentials, snapshots: SnapshotStore(fileURL: snapshotsURL))
    let camera = try model.add(name: "Original", address: "rtsp://localhost/original")
    defer { try? credentials.remove(id: camera.id) }
    try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
    try Data([1]).write(to: snapshotsURL.appendingPathComponent("child"))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: snapshotsURL.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: snapshotsURL.path)
    }
    XCTAssertThrowsError(
      try model.edit(id: camera.id, name: "Changed", address: "rtsp://localhost/changed"))
    XCTAssertEqual(model.selectedCamera?.name, "Original")
    XCTAssertEqual(try credentials.read(id: camera.id)?.rawValue, "rtsp://localhost/original")
    let reopened = try CameraCatalog(fileURL: folder.appendingPathComponent("catalog.json"))
    XCTAssertEqual(reopened.selectedCamera?.name, "Original")
  }

  func testAdHocProcessDoesNotClaimSharedContainerAccess() {
    XCTAssertFalse(SharedContainer.hasSignedGroupAccess("group.com.harper.camera-bar"))
  }

  func testWidgetReadsActualImageAndDateAndRejectsCorruption() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let store = SnapshotStore(fileURL: file)
    XCTAssertNil(WidgetSnapshot.load(from: store))
    let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
      NSColor.red.setFill()
      rect.fill()
      return true
    }
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
    let data = try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [:]))
    let date = Date(timeIntervalSince1970: 50)
    try store.publish(
      Snapshot(cameraID: UUID(), cameraName: "Porch", jpegData: data, capturedAt: date))
    XCTAssertEqual(WidgetSnapshot.load(from: store)?.capturedAt, date)
    XCTAssertEqual(WidgetSnapshot.load(from: store)?.cameraName, "Porch")
    try Data("corrupt".utf8).write(to: file)
    XCTAssertNil(WidgetSnapshot.load(from: store))
  }
}
