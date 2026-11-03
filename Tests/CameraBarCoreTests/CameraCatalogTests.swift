// ABOUTME: Exercises camera catalog changes against real temporary files.
// ABOUTME: Checks selection, metadata privacy, invalid state, and persistence failures.
import Foundation
import XCTest

@testable import CameraBarCore

final class CameraCatalogTests: XCTestCase {
  private var directory: URL!
  private var fileURL: URL { directory.appendingPathComponent("catalog.json") }

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: directory)
  }

  func testMissingCatalogStartsEmpty() throws {
    let catalog = try CameraCatalog(fileURL: fileURL)
    XCTAssertTrue(catalog.cameras.isEmpty)
    XCTAssertNil(catalog.selectedCameraID)
  }

  func testAddRenameSelectAndDeletePersist() throws {
    let catalog = try CameraCatalog(fileURL: fileURL)
    let porch = try catalog.add(name: " Porch ")
    let garage = try catalog.add(name: "Garage")
    XCTAssertEqual(catalog.selectedCameraID, porch.id)
    try catalog.rename(id: garage.id, name: " Driveway ")
    try catalog.select(id: garage.id)
    let reopened = try CameraCatalog(fileURL: fileURL)
    XCTAssertEqual(reopened.selectedCamera?.name, "Driveway")
    XCTAssertEqual(reopened.cameras.map(\.id), [porch.id, garage.id])
    try reopened.remove(id: garage.id)
    XCTAssertEqual(try CameraCatalog(fileURL: fileURL).selectedCameraID, porch.id)
    try reopened.remove(id: porch.id)
    XCTAssertTrue(try CameraCatalog(fileURL: fileURL).cameras.isEmpty)
    XCTAssertNil(reopened.selectedCameraID)
  }

  func testCanExplicitlyClearSelection() throws {
    let catalog = try CameraCatalog(fileURL: fileURL)
    _ = try catalog.add(name: "Porch")
    try catalog.select(id: nil)
    XCTAssertNil(try CameraCatalog(fileURL: fileURL).selectedCameraID)
  }

  func testInvalidChangesDoNotMutateCatalog() throws {
    let catalog = try CameraCatalog(fileURL: fileURL)
    let camera = try catalog.add(name: "Porch")
    let original = try Data(contentsOf: fileURL)
    XCTAssertThrowsError(try catalog.add(name: " "))
    XCTAssertThrowsError(try catalog.rename(id: camera.id, name: ""))
    XCTAssertThrowsError(try catalog.rename(id: UUID(), name: "Lost"))
    XCTAssertThrowsError(try catalog.select(id: UUID()))
    XCTAssertThrowsError(try catalog.remove(id: UUID()))
    XCTAssertEqual(try Data(contentsOf: fileURL), original)
    XCTAssertEqual(catalog.cameras, [camera])
  }

  func testCatalogContainsOnlyCameraIDsAndNames() throws {
    let catalog = try CameraCatalog(fileURL: fileURL)
    _ = try catalog.add(name: "Porch")
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
    XCTAssertEqual(Set(json.keys), ["cameras", "selectedCameraID"])
    let cameras = try XCTUnwrap(json["cameras"] as? [[String: Any]])
    XCTAssertEqual(Set(try XCTUnwrap(cameras.first).keys), ["id", "name"])
  }

  func testCorruptCatalogIsSurfacedAndNotOverwritten() throws {
    let bytes = Data("not json".utf8)
    try bytes.write(to: fileURL)
    XCTAssertThrowsError(try CameraCatalog(fileURL: fileURL))
    XCTAssertEqual(try Data(contentsOf: fileURL), bytes)
  }

  func testDanglingSelectionAndDuplicateIDsAreRejected() throws {
    let id = UUID()
    for json in [
      "{\"cameras\":[],\"selectedCameraID\":\"\(id)\"}",
      "{\"cameras\":[{\"id\":\"\(id)\",\"name\":\"A\"},{\"id\":\"\(id)\",\"name\":\"B\"}]}",
    ] {
      try Data(json.utf8).write(to: fileURL)
      XCTAssertThrowsError(try CameraCatalog(fileURL: fileURL))
    }
  }

  func testFailedWriteDoesNotChangeInMemoryState() throws {
    let catalog = try CameraCatalog(fileURL: fileURL)
    let camera = try catalog.add(name: "Porch")
    try FileManager.default.removeItem(at: directory)
    try Data().write(to: directory)
    defer {
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    XCTAssertThrowsError(try catalog.rename(id: camera.id, name: "Garage"))
    XCTAssertEqual(catalog.cameras, [camera])
  }
}
