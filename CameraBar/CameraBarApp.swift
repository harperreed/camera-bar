// ABOUTME: Hosts the menu bar viewer, camera settings, and widget refresh loop.
// ABOUTME: Routes widget links to the viewer and stops playback on termination.
import AppKit
import CameraBarCore
import SwiftUI
import WidgetKit

@main
@MainActor
final class CameraBarApp: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private var statusItem: NSStatusItem!
  private let popover = NSPopover()
  private var settingsWindow: NSWindow?
  private var controller: AppController!
  private var pendingViewer = false
  private static var delegate: CameraBarApp?

  static func main() {
    let app = NSApplication.shared
    delegate = CameraBarApp()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    installMenu()
    controller = AppController()
    controller.showSettings = { [weak self] in self?.openSettings() }
    controller.showViewer = { [weak self] in self?.openViewer() }
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "video", accessibilityDescription: "Camera Bar")
    statusItem.button?.setAccessibilityLabel("Camera Bar")
    statusItem.button?.target = self
    statusItem.button?.action = #selector(toggleViewer)
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 480, height: 430)
    popover.delegate = self
    popover.contentViewController = NSHostingController(
      rootView: ViewerRoot(controller: controller))
    controller.restart()
    if pendingViewer { openViewer() }
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    if pendingViewer { openViewer() }
  }

  func applicationDidUpdate(_ notification: Notification) {
    if pendingViewer, NSApp.isActive { openViewer() }
  }

  private func installMenu() {
    let menu = NSMenu()
    let application = NSMenu()
    application.addItem(
      withTitle: "Quit Camera Bar", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    let applicationItem = menu.addItem(withTitle: "Camera Bar", action: nil, keyEquivalent: "")
    applicationItem.submenu = application
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let editItem = menu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
    editItem.submenu = edit
    NSApp.mainMenu = menu
  }

  @objc private func toggleViewer() {
    if popover.isShown { popover.performClose(nil) } else { openViewer() }
  }

  private func openViewer() {
    pendingViewer = true
    guard let button = statusItem?.button else { return }
    guard NSApp.isActive else {
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    // Cold launches can activate before the status item's window finishes layout.
    guard let anchorWindow = button.window, anchorWindow.isVisible,
      !anchorWindow.frame.isEmpty, !button.isHiddenOrHasHiddenAncestor,
      button.visibleRect.intersects(button.bounds)
    else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    guard popover.isShown else { return }
    pendingViewer = false
    controller.setViewerOpen(true)
    // A hidden or crowded menu bar can leave the anchor outside the visible screen.
    if let window = popover.contentViewController?.view.window,
      let screen = button.window?.screen ?? NSScreen.main
    {
      var frame = window.frame
      let visible = screen.visibleFrame
      frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
      frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
      window.setFrame(frame, display: true)
    }
  }

  func popoverDidClose(_ notification: Notification) {
    controller.engine.parkVideo()
    controller.setViewerOpen(false)
  }

  private func openSettings() {
    popover.performClose(nil)
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
      window.title = "Camera Bar Settings"
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(
        rootView: SettingsRoot(controller: controller))
      window.center()
      settingsWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    if urls.contains(where: { $0.scheme == "camerabar" && $0.host == "viewer" }) { openViewer() }
  }

  func applicationWillTerminate(_ notification: Notification) { controller?.stop() }
}
