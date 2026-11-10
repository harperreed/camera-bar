// ABOUTME: Defines the restrained housing and display colors used by Camera Bar.
// ABOUTME: Keeps the viewer and snapshot widget visually consistent.
import SwiftUI

enum MonitorTheme {
  static let housing = Color(red: 36 / 255, green: 41 / 255, blue: 42 / 255)
  static let display = Color(red: 16 / 255, green: 20 / 255, blue: 21 / 255)
  static let text = Color(red: 238 / 255, green: 241 / 255, blue: 236 / 255)
  static let secondary = Color(red: 167 / 255, green: 176 / 255, blue: 171 / 255)
  static let live = Color(red: 151 / 255, green: 196 / 255, blue: 156 / 255)
  static let edge = Color.white.opacity(0.1)
}
