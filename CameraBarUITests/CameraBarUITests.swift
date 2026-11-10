// ABOUTME: Drives the real app through camera editing, selection, playback, and failures.
// ABOUTME: Uses a live RTSP fixture and removes its uniquely named cameras afterward.
import AppKit
import CameraBarCore
import XCTest

final class CameraBarUITests: XCTestCase {
  private var catalogURL: URL?
  private var originalIDs: Set<UUID> = []
  private var originalSelection: UUID?
  private var ownedIDs: Set<UUID> = []
  private var fixtureNames: Set<String> = []
  private var restoreRunningApp = false
  private var didLaunch = false

  override func tearDown() async throws {
    guard didLaunch, let catalogURL else { return }
    await MainActor.run {
      continueAfterFailure = true
      XCUIApplication().terminate()
    }
    let owned = ownedIDs
    let original = originalIDs
    let names = fixtureNames
    let selection = originalSelection
    let cleanup = await Task.detached {
      let catalog = try CameraCatalog(fileURL: catalogURL)
      var failure: Error?
      for camera in catalog.cameras
      where owned.contains(camera.id)
        || (!original.contains(camera.id) && names.contains(camera.name))
      {
        do {
          try Self.removeCredential(id: camera.id)
          try catalog.remove(id: camera.id)
        } catch { failure = failure ?? error }
      }
      do {
        if selection == nil || catalog.cameras.contains(where: { $0.id == selection }) {
          try catalog.select(id: selection)
        }
      } catch { failure = failure ?? error }
      if let failure { throw failure }
    }.result
    if restoreRunningApp { await MainActor.run { XCUIApplication().launch() } }
    try cleanup.get()
  }

  private static func removeCredential(id: UUID) throws {
    // The UI runner cannot delete another executable's Keychain items through SecItemDelete.
    let command = Process()
    command.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    command.arguments = [
      "delete-generic-password", "-s", "com.harper.camera-bar.addresses", "-a", id.uuidString,
    ]
    let output = Pipe()
    command.standardOutput = output
    command.standardError = output
    try command.run()
    let diagnostic = output.fileHandleForReading.readDataToEndOfFile()
    command.waitUntilExit()
    // security maps errSecItemNotFound to exit 44; also check its diagnostic.
    let absent =
      command.terminationStatus == 44
      && String(decoding: diagnostic, as: UTF8.self)
        .contains("The specified item could not be found in the keychain.")
    guard command.terminationStatus == 0 || absent else {
      throw NSError(
        domain: "CameraBarUITestCleanup", code: Int(command.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "Could not remove test credential \(id)"])
    }
  }

  @MainActor
  func testCameraLifecycle() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    restoreRunningApp = app.state != .notRunning
    let file = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true
    ).appendingPathComponent("CameraBar/cameras.json")
    let original = try CameraCatalog(fileURL: file)
    catalogURL = file
    originalIDs = Set(original.cameras.map(\.id))
    originalSelection = original.selectedCameraID
    let initiallyEmpty = original.cameras.isEmpty
    let name = "UI Test \(UUID().uuidString)"
    fixtureNames = [name + " A", name + " B", name + " Edited"]
    app.launch()
    didLaunch = true
    try openViewer()
    let settings = app.buttons["Camera settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10))
    if initiallyEmpty { attach(app.popovers.firstMatch, name: "Empty viewer") }
    settings.click()
    try addCamera(app, name: name + " A")
    try addCamera(app, name: name + " B")
    attach(app.windows["Camera Bar Settings"], name: "Camera settings")
    app.buttons["Select \(name) B"].click()
    app.buttons["Show viewer"].click()
    XCTAssertTrue(app.staticTexts["Live · muted"].waitForExistence(timeout: 20))
    XCTAssertEqual(app.popUpButtons.firstMatch.value as? String, name + " B")
    let screenshot = XCTAttachment(screenshot: app.popovers.firstMatch.screenshot())
    screenshot.name = "Live RTSP viewer"
    screenshot.lifetime = .keepAlways
    add(screenshot)

    app.terminate()
    try openViewer()
    XCTAssertTrue(app.staticTexts["Live · muted"].waitForExistence(timeout: 20))
    XCTAssertEqual(app.popUpButtons.firstMatch.value as? String, name + " B")
    app.buttons["Camera settings"].click()
    app.buttons["Edit \(name) B"].click()
    let nameField = app.textFields["Camera name"]
    nameField.click()
    nameField.typeKey("a", modifierFlags: .command)
    nameField.typeText(name + " Edited")
    let address = app.secureTextFields["RTSP address"]
    address.click()
    address.typeKey("a", modifierFlags: .command)
    address.typeText("rtsp://127.0.0.1:18554/missing")
    app.buttons["Save camera"].click()
    XCTAssertTrue(app.staticTexts[name + " Edited"].waitForExistence(timeout: 5))
    app.buttons["Show viewer"].click()
    XCTAssertTrue(app.staticTexts["Camera unavailable"].firstMatch.waitForExistence(timeout: 20))
    XCTAssertTrue(app.buttons["Retry"].exists)
    XCTAssertTrue(app.buttons["Retry"].isHittable)
    attach(app.popovers.firstMatch, name: "Unavailable camera")
    app.buttons["Camera settings"].click()
    removeCamera(app, name: name + " Edited")
    removeCamera(app, name: name + " A")
    if initiallyEmpty {
      app.buttons["Show viewer"].click()
      XCTAssertTrue(app.staticTexts["Your camera, one click away"].waitForExistence(timeout: 5))
    }
  }

  @MainActor
  private func attach(_ element: XCUIElement, name: String) {
    let screenshot = XCTAttachment(screenshot: element.screenshot())
    screenshot.name = name
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  private func openViewer() throws {
    NSWorkspace.shared.open(try XCTUnwrap(URL(string: "camerabar://viewer")))
  }

  @MainActor
  private func addCamera(_ app: XCUIApplication, name: String) throws {
    let add = app.buttons["Add camera"]
    XCTAssertTrue(add.waitForExistence(timeout: 5))
    add.click()
    let nameField = app.textFields["Camera name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Save camera"].isEnabled)
    attach(app.windows["Camera Bar Settings"], name: "Camera editor")
    nameField.click()
    nameField.typeText(name)
    let address = app.secureTextFields["RTSP address"]
    address.click()
    address.typeText("rtsp://127.0.0.1:18554/live")
    app.buttons["Save camera"].click()
    XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    let catalog = try CameraCatalog(fileURL: XCTUnwrap(catalogURL))
    ownedIDs.formUnion(
      catalog.cameras.filter { $0.name == name && !originalIDs.contains($0.id) }.map(\.id))
  }

  @MainActor
  private func removeCamera(_ app: XCUIApplication, name: String) {
    app.buttons["Remove \(name)"].click()
    app.buttons["Remove camera"].click()
    XCTAssertFalse(app.staticTexts[name].exists)
  }
}
