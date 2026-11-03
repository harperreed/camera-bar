// ABOUTME: Plays one muted RTSP feed and captures decoded frames with bounded waits.
// ABOUTME: Keeps a drawable alive offscreen and cancels work when playback changes.
import AppKit
import CameraBarCore
import Foundation
import VLCKit

enum PlaybackError: Error, Equatable { case cancelled, unavailable, timedOut }

@MainActor
final class PlaybackEngine {
  struct Frame {
    let jpegData: Data
    let capturedAt: Date
  }
  let videoView = VLCVideoView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
  private let library: VLCLibrary
  private let session: CBPlaybackSession
  private var player: VLCMediaPlayer { session.player }
  private var transition: Task<Void, Never>?
  private var readyGeneration: UUID?
  private var running = false
  private var generation = UUID()
  private let window: NSWindow
  var isRunning: Bool { running || !session.stopped }
  var isPlaying: Bool { player.isPlaying }
  var displayedFrames: Int32 { player.media?.statistics.displayedPictures ?? 0 }
  var isMuted: Bool { player.audio?.isMuted ?? true }
  var hasVideo: Bool { player.hasVideoOut == true && player.videoSize.width > 0 }

  init() {
    // VLCKit defaults to verbose wire logging, including RTSP addresses.
    UserDefaults.standard.set(
      [
        "--quiet", "--verbose=0", "--no-color", "--no-video-title-show",
        "--no-snapshot-preview", "--no-osd", "--vout=macosx", "--no-audio",
      ], forKey: "VLCParams")
    library = VLCLibrary.shared()
    library.loggers = nil
    session = CBPlaybackSession(library: library)
    window = NSWindow(
      contentRect: NSRect(x: -10000, y: -10000, width: 640, height: 360),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.stationary, .ignoresCycle]
    parkVideo()
  }

  func start(_ address: RTSPAddress) {
    stop()
    running = true
    let token = generation
    transition = Task { [weak self] in
      guard let self, !Task.isCancelled, token == generation else { return }
      await session.stop()
      guard !Task.isCancelled, running, token == generation else { return }
      let media = VLCMedia(url: address.url)
      media.addOption(":rtsp-tcp")
      media.addOption(":verbose=0")
      player.media = media
      player.drawable = videoView
      player.audio?.isMuted = true
      player.play()
      player.audio?.isMuted = true
      readyGeneration = token
    }
  }

  func stop() {
    generation = UUID()
    readyGeneration = nil
    running = false
    transition?.cancel()
    transition = nil
    session.stop(completionHandler: {})
  }

  func parkVideo() {
    videoView.removeFromSuperview()
    window.contentView = videoView
    window.orderFront(nil)
  }

  func capture(timeout: TimeInterval = 15) async throws -> Frame {
    guard running else { throw PlaybackError.cancelled }
    let active = player
    let token = generation
    let deadline = Date().addingTimeInterval(timeout)
    while readyGeneration != token {
      try validate(token: token, deadline: deadline)
      try await Task.sleep(for: .milliseconds(50))
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "CameraBar-\(UUID())")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("frame.png")
    let initialFrames = displayedFrames
    while !hasVideo || !isPlaying || displayedFrames <= initialFrames {
      try validate(token: token, deadline: deadline)
      if active.state == .error || active.state == .ended { throw PlaybackError.unavailable }
      try await Task.sleep(for: .milliseconds(100))
    }
    while true {
      try validate(token: token, deadline: deadline)
      guard hasVideo, isPlaying else { throw PlaybackError.unavailable }
      let saved = await session.snapshot(atPath: file.path)
      try validate(token: token, deadline: deadline)
      // VLC waits only 500 ms for a frame per request. Keep requesting within
      // the deadline so slow streams can supply their next frame.
      if !saved { continue }
      guard let data = try? Data(contentsOf: file),
        let image = NSBitmapImageRep(data: data),
        let jpeg = image.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
      else { throw PlaybackError.unavailable }
      return Frame(jpegData: jpeg, capturedAt: Date())
    }
  }

  private func validate(token: UUID, deadline: Date) throws {
    guard !Task.isCancelled, token == generation, running else {
      throw PlaybackError.cancelled
    }
    guard Date() < deadline else { throw PlaybackError.timedOut }
  }
}
