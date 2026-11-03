// ABOUTME: Shares the latest camera image and capture metadata as one record.
// ABOUTME: Publishes snapshots atomically so widget readers cannot mix two captures.
import Foundation

public struct Snapshot: Codable, Equatable, Sendable {
  public let cameraID: UUID
  public let cameraName: String
  public let jpegData: Data
  public let capturedAt: Date

  public init(cameraID: UUID, cameraName: String, jpegData: Data, capturedAt: Date) {
    self.cameraID = cameraID
    self.cameraName = cameraName
    self.jpegData = jpegData
    self.capturedAt = capturedAt
  }
}

public struct SnapshotStore: Sendable {
  private let fileURL: URL

  public init(fileURL: URL) { self.fileURL = fileURL }

  public func publish(_ snapshot: Snapshot) throws {
    let data = try JSONEncoder().encode(snapshot)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: fileURL, options: .atomic)
  }

  public func read(expectedCameraID: UUID? = nil) throws -> Snapshot? {
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch CocoaError.fileReadNoSuchFile {
      return nil
    }
    let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
    guard expectedCameraID == nil || expectedCameraID == snapshot.cameraID else { return nil }
    return snapshot
  }

  /// Call when selection changes, before starting the selected camera's capture.
  public func clear() throws {
    do {
      try FileManager.default.removeItem(at: fileURL)
    } catch CocoaError.fileNoSuchFile {
      return
    }
  }
}
