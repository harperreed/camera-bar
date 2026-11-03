// ABOUTME: Verifies actual RTSP decoding and bounded failure using the local fixture.
// ABOUTME: Confirms real frame capture, muted playback, and cancellation.
import AppKit
import CameraBarCore
import VLCKit
import XCTest

@MainActor
final class PlaybackTests: XCTestCase {
  func testRealRTSPFrameAndCancellation() async throws {
    _ = NSApplication.shared
    let engine = PlaybackEngine()
    defer { engine.stop() }
    engine.start(
      try RTSPAddress(
        "rtsp://camera-bar-user:camera-bar-password@127.0.0.1:18554/live?token=log-redaction-probe")
    )
    let snapshot = try await engine.capture(timeout: 12)
    XCTAssertGreaterThan(snapshot.jpegData.count, 500)
    XCTAssertGreaterThan(try XCTUnwrap(NSImage(data: snapshot.jpegData)).size.width, 100)
    XCTAssertLessThan(abs(snapshot.capturedAt.timeIntervalSinceNow), 15)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: snapshot.jpegData))
    let colors = stride(from: 10, to: bitmap.pixelsWide, by: 40).compactMap {
      bitmap.colorAt(x: $0, y: bitmap.pixelsHigh / 3)?.usingColorSpace(.deviceRGB)
    }
    XCTAssertGreaterThan(
      (colors.map(\.redComponent).max() ?? 0) - (colors.map(\.redComponent).min() ?? 0), 0.5)
    let attachment = XCTAttachment(data: snapshot.jpegData, uniformTypeIdentifier: "public.jpeg")
    attachment.name = "Real RTSP test pattern"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertTrue(engine.isMuted)
    let pending = Task { try await engine.capture(timeout: 12) }
    engine.stop()
    do {
      _ = try await pending.value
      XCTFail("Stopped playback must not yield a frame")
    } catch { XCTAssertEqual(error as? PlaybackError, .cancelled) }
  }

  func testRapidRestartCapturesOnlyCurrentStream() async throws {
    _ = NSApplication.shared
    let engine = PlaybackEngine()
    defer { engine.stop() }
    for _ in 0..<4 {
      engine.start(try RTSPAddress("rtsp://127.0.0.1:18554/missing"))
      let oldCapture = Task { try await engine.capture(timeout: 3) }
      await Task.yield()
      engine.start(try RTSPAddress("rtsp://127.0.0.1:18554/live"))
      do {
        _ = try await oldCapture.value
        XCTFail("Old capture must be cancelled")
      } catch { XCTAssertEqual(error as? PlaybackError, .cancelled) }
      let frame = try await engine.capture(timeout: 12)
      XCTAssertNotNil(NSImage(data: frame.jpegData))
    }
  }

  func testBackgroundStopsAndViewerRestartsRealPlayback() async throws {
    _ = NSApplication.shared
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let credentials = CredentialStore(service: "CameraBarTests.\(UUID())")
    let store = SnapshotStore(fileURL: folder.appendingPathComponent("snapshot.json"))
    let state = CameraState(
      catalog: try CameraCatalog(fileURL: folder.appendingPathComponent("cameras.json")),
      credentials: credentials, snapshots: store)
    let camera = try state.add(name: "Fixture", address: "rtsp://127.0.0.1:18554/live")
    defer { try? credentials.remove(id: camera.id) }
    let controller = AppController(state: state)
    defer { controller.stop() }
    controller.restart()
    let deadline = Date().addingTimeInterval(15)
    while try store.read() == nil && Date() < deadline {
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertNotNil(try store.read())
    let stopDeadline = Date().addingTimeInterval(5)
    while controller.engine.isRunning && Date() < stopDeadline {
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertFalse(controller.engine.isRunning)
    controller.setViewerOpen(true)
    let viewerDeadline = Date().addingTimeInterval(15)
    while !controller.isLive && Date() < viewerDeadline {
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertTrue(controller.isLive)
    XCTAssertTrue(controller.engine.isRunning)
    try await Task.sleep(for: .seconds(3))
    XCTAssertTrue(controller.isLive, "A healthy live feed must stay live after initial capture")
    controller.setViewerOpen(false)
    let closedDeadline = Date().addingTimeInterval(15)
    while controller.engine.isRunning && Date() < closedDeadline {
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertFalse(controller.engine.isRunning)
  }

  func testFailedCaptureKeepsSameCameraSnapshotAndCaptureDate() async throws {
    _ = NSApplication.shared
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let engine = PlaybackEngine()
    engine.start(try RTSPAddress("rtsp://127.0.0.1:18554/live"))
    let frame = try await engine.capture(timeout: 12)
    engine.stop()
    let credentials = CredentialStore(service: "CameraBarTests.\(UUID())")
    let store = SnapshotStore(fileURL: folder.appendingPathComponent("snapshot.json"))
    let state = CameraState(
      catalog: try CameraCatalog(fileURL: folder.appendingPathComponent("catalog.json")),
      credentials: credentials, snapshots: store)
    let camera = try state.add(name: "Offline", address: "rtsp://127.0.0.1:18554/missing")
    defer { try? credentials.remove(id: camera.id) }
    try state.publish(
      jpegData: frame.jpegData, capturedAt: frame.capturedAt, generation: state.generation)
    let original = try XCTUnwrap(store.read())
    let controller = AppController(state: state)
    defer { controller.stop() }
    controller.restart()
    let deadline = Date().addingTimeInterval(20)
    while controller.status != "Camera unavailable" && Date() < deadline {
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertEqual(controller.status, "Camera unavailable")
    XCTAssertEqual(try store.read(), original)
    let stopDeadline = Date().addingTimeInterval(5)
    while controller.engine.isRunning && Date() < stopDeadline {
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertFalse(controller.engine.isRunning)
  }

  func testSnapshotWithoutVideoReturnsFailure() {
    _ = NSApplication.shared
    let engine = PlaybackEngine()
    defer { engine.stop() }
    let empty = VLCMediaPlayer(library: VLCLibrary.shared())
    XCTAssertFalse(CBTakeSnapshot(empty, "/dev/null", 1280, 0))
  }

  func testSparseStreamCapturesWithinOriginalDeadline() async throws {
    _ = NSApplication.shared
    let engine = PlaybackEngine()
    defer { engine.stop() }
    engine.start(try RTSPAddress("rtsp://127.0.0.1:18554/sparse"))
    // Warm the decoder separately so this measures snapshot acquisition, not startup.
    let readyDeadline = Date().addingTimeInterval(30)
    while (!engine.hasVideo || engine.displayedFrames == 0) && Date() < readyDeadline {
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertTrue(engine.hasVideo)
    XCTAssertGreaterThan(engine.displayedFrames, 0)
    for _ in 0..<3 {
      let snapshot = try await engine.capture(timeout: 12)
      XCTAssertNotNil(NSImage(data: snapshot.jpegData))
    }
  }

  func testLowFrameRateStreamStillCaptures() async throws {
    _ = NSApplication.shared
    let engine = PlaybackEngine()
    defer { engine.stop() }
    engine.start(try RTSPAddress("rtsp://127.0.0.1:18554/slow"))
    let snapshot = try await engine.capture(timeout: 12)
    XCTAssertNotNil(NSImage(data: snapshot.jpegData))
    XCTAssertGreaterThan(snapshot.jpegData.count, 500)
  }

  func testOfflineCaptureIsBounded() async throws {
    _ = NSApplication.shared
    let engine = PlaybackEngine()
    defer { engine.stop() }
    engine.start(try RTSPAddress("rtsp://127.0.0.1:18554/live"))
    _ = try await engine.capture(timeout: 12)
    engine.start(try RTSPAddress("rtsp://127.0.0.1:18554/missing"))
    let started = Date()
    do {
      _ = try await engine.capture(timeout: 2)
      XCTFail("Missing stream must fail")
    } catch { XCTAssertLessThan(Date().timeIntervalSince(started), 5) }
  }
}
