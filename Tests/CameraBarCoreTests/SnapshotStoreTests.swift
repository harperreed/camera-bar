// ABOUTME: Verifies whole snapshot records using actual shared-file reads and writes.
// ABOUTME: Covers camera matching, capture dates, clearing, corruption, and atomic replacement.
import Foundation
import XCTest

@testable import CameraBarCore

final class SnapshotStoreTests: XCTestCase {
  private var directory: URL!
  private var fileURL: URL { directory.appendingPathComponent("snapshot.json") }

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: directory)
  }

  func testMissingSnapshotHasNoImage() throws {
    XCTAssertNil(try SnapshotStore(fileURL: fileURL).read())
  }

  func testRoundTripPreservesCaptureDateAndCamera() throws {
    let snapshot = Snapshot(
      cameraID: UUID(), cameraName: "Porch", jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
      capturedAt: Date(timeIntervalSince1970: 1_700_000_000.25))
    try SnapshotStore(fileURL: fileURL).publish(snapshot)
    let reopened = SnapshotStore(fileURL: fileURL)
    XCTAssertEqual(try reopened.read(expectedCameraID: snapshot.cameraID), snapshot)
    XCTAssertEqual(try reopened.read(), snapshot)
    XCTAssertNil(try reopened.read(expectedCameraID: UUID()))
  }

  func testClearRemovesPreviousCameraAndIsIdempotent() throws {
    let store = SnapshotStore(fileURL: fileURL)
    try store.publish(
      Snapshot(cameraID: UUID(), cameraName: "Porch", jpegData: Data([1]), capturedAt: Date()))
    try store.clear()
    XCTAssertNil(try store.read())
    XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    XCTAssertNoThrow(try store.clear())
  }

  func testCorruptSnapshotIsSurfaced() throws {
    try Data("broken".utf8).write(to: fileURL)
    XCTAssertThrowsError(try SnapshotStore(fileURL: fileURL).read())
  }

  func testConcurrentReadersSeeWholeRecords() async throws {
    let store = SnapshotStore(fileURL: fileURL)
    let id = UUID()
    let first = Snapshot(
      cameraID: id, cameraName: "A", jpegData: Data(repeating: 1, count: 32_768),
      capturedAt: Date(timeIntervalSince1970: 1))
    let second = Snapshot(
      cameraID: id, cameraName: "B", jpegData: Data(repeating: 2, count: 32_768),
      capturedAt: Date(timeIntervalSince1970: 2))
    try store.publish(first)
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        for index in 0..<50 { try store.publish(index.isMultiple(of: 2) ? first : second) }
      }
      group.addTask {
        for _ in 0..<100 {
          let value = try XCTUnwrap(store.read())
          XCTAssertTrue(value == first || value == second)
        }
      }
      try await group.waitForAll()
    }
  }
}
