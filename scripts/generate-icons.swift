// ABOUTME: Draws Camera Bar's monitor app icon and template menu bar mark.
// ABOUTME: Run from any directory to regenerate the checked-in macOS asset catalog.
import AppKit
import Foundation

let usage = """
  Usage: swift scripts/generate-icons.swift [--help]
  Regenerates CameraBar/Assets.xcassets using native vector drawing.
  Run after changing this artwork; generated PNGs and catalog metadata belong in Git.
  """
if CommandLine.arguments.dropFirst().contains("--help") {
  print(usage)
  exit(0)
}
guard CommandLine.arguments.count == 1 else {
  fputs("Unknown argument.\n\(usage)\n", stderr)
  exit(1)
}
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("CameraBar/Assets.xcassets")

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
  NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func rounded(_ rect: CGRect, radius: CGFloat, fill: NSColor) {
  fill.setFill()
  NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func render(size: Int, coordinates: CGFloat, draw: () -> Void) throws -> Data {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else { throw CocoaError(.fileWriteUnknown) }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.cgContext.scaleBy(x: CGFloat(size) / coordinates, y: CGFloat(size) / coordinates)
  draw()
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }
  return png
}

func appIcon() {
  let body = CGRect(x: 90, y: 90, width: 844, height: 844)
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
  shadow.shadowBlurRadius = 24
  shadow.shadowOffset = CGSize(width: 0, height: -12)
  NSGraphicsContext.saveGraphicsState()
  shadow.set()
  rounded(body, radius: 184, fill: color(36, 41, 42))
  NSGraphicsContext.restoreGraphicsState()
  let outline = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 182, yRadius: 182)
  outline.lineWidth = 3
  NSColor.white.withAlphaComponent(0.12).setStroke()
  outline.stroke()

  // The screen's light rim reads clearly even in the smallest Finder icon.
  rounded(CGRect(x: 185, y: 265, width: 654, height: 486), radius: 69, fill: color(211, 218, 211))
  rounded(CGRect(x: 205, y: 285, width: 614, height: 446), radius: 52, fill: color(11, 15, 16))
  let screen = NSBezierPath(
    roundedRect: CGRect(x: 220, y: 300, width: 584, height: 416), xRadius: 40, yRadius: 40)
  NSGradient(starting: color(44, 54, 54), ending: color(16, 20, 21))?.draw(in: screen, angle: -90)
  rounded(CGRect(x: 441, y: 203, width: 142, height: 23), radius: 11, fill: color(167, 176, 171))
  rounded(CGRect(x: 749, y: 199, width: 27, height: 27), radius: 13.5, fill: color(151, 196, 156))
}

func menuBar() {
  let frame = NSBezierPath(
    roundedRect: CGRect(x: 1.5, y: 4.5, width: 15, height: 11), xRadius: 2, yRadius: 2)
  frame.lineWidth = 1.5
  NSColor.black.setStroke()
  frame.stroke()
  rounded(CGRect(x: 6, y: 1, width: 6, height: 1.5), radius: 0.75, fill: .black)
  rounded(CGRect(x: 14, y: 1, width: 1.5, height: 1.5), radius: 0.75, fill: .black)
}

func writeJSON(_ value: [String: Any], to url: URL) throws {
  let data = try JSONSerialization.data(
    withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
  try (data + Data("\n".utf8)).write(to: url, options: .atomic)
}

do {
  let appSet = catalog.appendingPathComponent("AppIcon.appiconset")
  let menuSet = catalog.appendingPathComponent("MenuBar.imageset")
  for directory in [appSet, menuSet] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  let info: [String: Any] = ["author": "xcode", "version": 1]
  try writeJSON(["info": info], to: catalog.appendingPathComponent("Contents.json"))
  var appImages: [[String: String]] = []
  for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
      let file = "monitor-\(points)@\(scale)x.png"
      try render(size: points * scale, coordinates: 1024, draw: appIcon)
        .write(to: appSet.appendingPathComponent(file), options: .atomic)
      appImages.append([
        "filename": file, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)",
      ])
    }
  }
  try writeJSON(
    ["images": appImages, "info": info], to: appSet.appendingPathComponent("Contents.json"))
  var menuImages: [[String: String]] = []
  for scale in [1, 2] {
    let file = "monitor@\(scale)x.png"
    try render(size: 18 * scale, coordinates: 18, draw: menuBar)
      .write(to: menuSet.appendingPathComponent(file), options: .atomic)
    menuImages.append(["filename": file, "idiom": "mac", "scale": "\(scale)x"])
  }
  try writeJSON(
    ["images": menuImages, "info": info, "properties": ["template-rendering-intent": "template"]],
    to: menuSet.appendingPathComponent("Contents.json"))
  print("Generated AppIcon and MenuBar assets in \(catalog.path)")
} catch {
  fputs("Could not generate icon assets: \(error.localizedDescription)\n", stderr)
  exit(1)
}
