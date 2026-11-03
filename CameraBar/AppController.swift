// ABOUTME: Coordinates live viewing and short periodic snapshot sessions.
// ABOUTME: Cancels stale work and publishes only successful frames to the widget.
import AppKit
import CameraBarCore
import Combine
import WidgetKit

@MainActor
final class AppController: ObservableObject {
  let engine = PlaybackEngine()
  let state: CameraState?
  @Published var status = "Choose a camera"
  @Published var isLive = false
  @Published var error: String?
  let widgetUnavailable: Bool
  var showSettings: () -> Void = {}
  var showViewer: () -> Void = {}
  private var captureTask: Task<Void, Never>?
  @Published private(set) var viewerOpen = false

  init(state: CameraState?, startupError: String? = nil) {
    self.state = state
    widgetUnavailable = state?.snapshots == nil
    error = startupError
  }

  convenience init() {
    do {
      let directory = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true
      ).appendingPathComponent("CameraBar")
      let state = CameraState(
        catalog: try CameraCatalog(fileURL: directory.appendingPathComponent("cameras.json")),
        credentials: CredentialStore(service: "com.harper.camera-bar.addresses"),
        snapshots: SharedContainer.snapshotStore())
      self.init(state: state)
    } catch {
      self.init(
        state: nil,
        startupError:
          "Camera settings could not be opened. Check access to Application Support and try again.")
    }
  }

  func perform(_ operation: () throws -> Void) -> Bool {
    do {
      try operation()
      error = nil
      restart()
      return true
    } catch is CameraError {
      error = "Enter a camera name and a valid rtsp:// address with a host."
    } catch {
      self.error = "Could not save this change. Check Keychain and storage access, then try again."
      restart()
    }
    return false
  }

  func setViewerOpen(_ visible: Bool) {
    guard visible != viewerOpen else { return }
    viewerOpen = visible
    restart()
  }

  func stop() {
    captureTask?.cancel()
    captureTask = nil
    engine.stop()
    isLive = false
  }

  func restart() {
    stop()
    WidgetCenter.shared.reloadAllTimelines()
    guard let state, let camera = state.selectedCamera else {
      status = "No camera selected"
      return
    }
    let address: RTSPAddress
    do {
      guard let saved = try state.address(id: camera.id) else {
        status = "Address unavailable — edit this camera"
        return
      }
      address = saved
    } catch {
      status = "Keychain unavailable — unlock it and retry"
      return
    }
    status = "Connecting…"
    let generation = state.generation
    captureTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        engine.start(address)
        do {
          let frame = try await engine.capture()
          guard !Task.isCancelled, generation == state.generation else { return }
          isLive = viewerOpen
          status = viewerOpen ? "Live · muted" : "Snapshot updated"
          do {
            try state.publish(
              jpegData: frame.jpegData, capturedAt: frame.capturedAt, generation: generation)
            WidgetCenter.shared.reloadAllTimelines()
          } catch {
            self.error = "The widget image could not be saved. Live video is still available."
          }
          if viewerOpen {
            try await monitorViewer()
          } else {
            engine.stop()
            try await Task.sleep(for: .seconds(300))
          }
        } catch {
          guard !Task.isCancelled, generation == state.generation else { return }
          isLive = false
          status = "Camera unavailable"
          engine.stop()
          do { try await Task.sleep(for: .seconds(viewerOpen ? 5 : 300)) } catch { return }
        }
        guard !Task.isCancelled, generation == state.generation else { return }
      }
    }
  }

  private func monitorViewer() async throws {
    var frames = engine.displayedFrames
    var lastFrame = Date()
    var lastCapture = Date()
    while !Task.isCancelled {
      try await Task.sleep(for: .seconds(1))
      if engine.displayedFrames != frames {
        frames = engine.displayedFrames
        lastFrame = Date()
      }
      guard engine.isPlaying, Date().timeIntervalSince(lastFrame) < 8 else {
        throw PlaybackError.unavailable
      }
      if Date().timeIntervalSince(lastCapture) >= 300, let state {
        let generation = state.generation
        let frame = try await engine.capture()
        guard !Task.isCancelled, generation == state.generation else {
          throw PlaybackError.cancelled
        }
        do {
          try state.publish(
            jpegData: frame.jpegData, capturedAt: frame.capturedAt, generation: generation)
          WidgetCenter.shared.reloadAllTimelines()
        } catch {
          self.error = "The widget image could not be saved. Live video is still available."
        }
        lastCapture = Date()
      }
    }
  }
}
