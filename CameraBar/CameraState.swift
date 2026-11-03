// ABOUTME: Owns camera selection and coordinates metadata with Keychain addresses.
// ABOUTME: Clears obsolete snapshots and rejects captures from older selections.
import CameraBarCore
import Combine
import Foundation

@MainActor
final class CameraState: ObservableObject {
  private let catalog: CameraCatalog
  private let credentials: CredentialStore
  let snapshots: SnapshotStore?
  @Published private(set) var cameras: [Camera]
  @Published private(set) var selectedCamera: Camera?
  private(set) var generation = UUID()

  init(catalog: CameraCatalog, credentials: CredentialStore, snapshots: SnapshotStore?) {
    self.catalog = catalog
    self.credentials = credentials
    self.snapshots = snapshots
    cameras = catalog.cameras
    selectedCamera = catalog.selectedCamera
  }

  func address(id: UUID) throws -> RTSPAddress? { try credentials.read(id: id) }

  @discardableResult
  func add(name: String, address: String) throws -> Camera {
    let validated = try RTSPAddress(address)
    let camera = try catalog.add(name: name)
    do { try credentials.write(validated, id: camera.id) } catch {
      try catalog.remove(id: camera.id)
      throw error
    }
    refresh()
    return camera
  }

  func edit(id: UUID, name: String, address: String) throws {
    _ = try Camera(id: id, name: name)
    let validated = try RTSPAddress(address)
    let previous = try credentials.read(id: id)
    if selectedCamera?.id == id { try invalidate() }
    try credentials.write(validated, id: id)
    do { try catalog.rename(id: id, name: name) } catch {
      if let previous {
        try credentials.write(previous, id: id)
      } else {
        try credentials.remove(id: id)
      }
      throw error
    }
    refresh()
  }

  func remove(id: UUID) throws {
    let previous = try credentials.read(id: id)
    if selectedCamera?.id == id { try invalidate() }
    try credentials.remove(id: id)
    do { try catalog.remove(id: id) } catch {
      if let previous { try credentials.write(previous, id: id) }
      throw error
    }
    refresh()
  }

  func select(id: UUID) throws {
    guard selectedCamera?.id != id else { return }
    try invalidate()
    try catalog.select(id: id)
    refresh()
  }

  func publish(jpegData: Data, capturedAt: Date, generation: UUID) throws {
    guard generation == self.generation, let camera = selectedCamera else { return }
    try snapshots?.publish(
      Snapshot(
        cameraID: camera.id, cameraName: camera.name,
        jpegData: jpegData, capturedAt: capturedAt))
  }

  private func invalidate() throws {
    generation = UUID()
    try snapshots?.clear()
  }

  private func refresh() {
    cameras = catalog.cameras
    selectedCamera = catalog.selectedCamera
  }
}
