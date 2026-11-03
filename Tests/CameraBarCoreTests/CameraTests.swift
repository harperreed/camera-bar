// ABOUTME: Verifies camera metadata and RTSP address validation.
// ABOUTME: Ensures invalid decoded metadata cannot bypass name validation.
import Foundation
import XCTest

@testable import CameraBarCore

final class CameraTests: XCTestCase {
  func testNameTrimsWhitespace() throws {
    XCTAssertEqual(try Camera(name: "  Porch\n").name, "Porch")
  }

  func testNameCannotBeEmpty() {
    XCTAssertThrowsError(try Camera(name: " \n"))
  }

  func testDecodedNameMustBeValid() throws {
    let data = Data("{\"id\":\"\(UUID())\",\"name\":\" \"}".utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(Camera.self, from: data))
  }

  func testRTSPAddressPreservesCredentialsAndPath() throws {
    let value = "rtsp://user:p%40ss@192.0.2.1:8554/camera?channel=1"
    XCTAssertEqual(try RTSPAddress(value).rawValue, value)
  }

  func testAddressRequiresRTSPSchemeAndHost() {
    for value in [
      "", "http://camera/live", "rtsps://camera/live", "rtsp:///live", "rtsp://", "camera",
    ] {
      XCTAssertThrowsError(try RTSPAddress(value), value)
    }
  }
}
