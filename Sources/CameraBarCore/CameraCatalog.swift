// ABOUTME: Persists camera metadata and the single selected camera.
// ABOUTME: Uses atomic file replacement and keeps addresses out of shared storage.
import Foundation

/// The app owns the catalog on one thread; the widget consumes only snapshots.
public final class CameraCatalog {
  private struct State: Codable {
    var cameras: [Camera] = []
    var selectedCameraID: UUID?
  }

  private let fileURL: URL
  private var state: State
  public var cameras: [Camera] { state.cameras }
  public var selectedCameraID: UUID? { state.selectedCameraID }
  public var selectedCamera: Camera? { cameras.first { $0.id == selectedCameraID } }

  public init(fileURL: URL) throws {
    self.fileURL = fileURL
    do {
      state = try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL))
    } catch CocoaError.fileReadNoSuchFile {
      state = State()
    }
    guard Set(cameras.map(\.id)).count == cameras.count,
      selectedCameraID == nil || selectedCamera != nil
    else { throw CameraError.invalidCatalog }
  }

  @discardableResult
  public func add(name: String) throws -> Camera {
    let camera = try Camera(name: name)
    var updated = state
    updated.cameras.append(camera)
    if updated.cameras.count == 1 { updated.selectedCameraID = camera.id }
    try save(updated)
    return camera
  }

  public func rename(id: UUID, name: String) throws {
    guard let index = cameras.firstIndex(where: { $0.id == id }) else {
      throw CameraError.unknownCamera
    }
    var updated = state
    updated.cameras[index] = try Camera(id: id, name: name)
    try save(updated)
  }

  public func remove(id: UUID) throws {
    guard cameras.contains(where: { $0.id == id }) else { throw CameraError.unknownCamera }
    var updated = state
    updated.cameras.removeAll { $0.id == id }
    if updated.selectedCameraID == id { updated.selectedCameraID = updated.cameras.first?.id }
    try save(updated)
  }

  public func select(id: UUID?) throws {
    guard id == nil || cameras.contains(where: { $0.id == id }) else {
      throw CameraError.unknownCamera
    }
    var updated = state
    updated.selectedCameraID = id
    try save(updated)
  }

  private func save(_ updated: State) throws {
    let data = try JSONEncoder().encode(updated)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: fileURL, options: .atomic)
    state = updated
  }
}
