// ABOUTME: Defines camera metadata separate from secret RTSP addresses.
// ABOUTME: Validates camera names and supported stream addresses.
import Foundation

public enum CameraError: Error, LocalizedError {
  case emptyName
  case invalidAddress
  case unknownCamera
  case invalidCatalog

  public var errorDescription: String? {
    switch self {
    case .emptyName: "Enter a camera name."
    case .invalidAddress: "Enter an rtsp:// address with a host."
    case .unknownCamera: "The camera no longer exists."
    case .invalidCatalog: "The saved camera catalog is invalid."
    }
  }
}

public struct Camera: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let name: String

  public init(id: UUID = UUID(), name: String) throws {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw CameraError.emptyName }
    self.id = id
    self.name = trimmedName
  }

  private enum CodingKeys: String, CodingKey { case id, name }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: values.decode(UUID.self, forKey: .id),
      name: values.decode(String.self, forKey: .name))
  }
}

public struct RTSPAddress: Equatable, Sendable {
  public let rawValue: String
  public let url: URL

  public init(_ value: String) throws {
    guard let url = URL(string: value, encodingInvalidCharacters: false),
      url.scheme?.lowercased() == "rtsp",
      let host = url.host, !host.isEmpty
    else { throw CameraError.invalidAddress }
    rawValue = value
    self.url = url
  }
}
