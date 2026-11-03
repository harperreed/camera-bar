// ABOUTME: Stores complete camera addresses only in the user's Keychain.
// ABOUTME: Reports status codes without exposing URLs or credentials.
import CameraBarCore
import Foundation
import Security

struct CredentialStore {
  let service: String
  struct Failure: Error { let status: OSStatus }

  private func query(id: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id.uuidString,
    ]
  }

  func read(id: UUID) throws -> RTSPAddress? {
    var request = query(id: id)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data,
      let value = String(data: data, encoding: .utf8)
    else { throw Failure(status: status) }
    return try RTSPAddress(value)
  }

  func write(_ address: RTSPAddress, id: UUID) throws {
    let attributes = [kSecValueData as String: Data(address.rawValue.utf8)]
    var status = SecItemUpdate(query(id: id) as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var request = query(id: id)
      request[kSecValueData as String] = Data(address.rawValue.utf8)
      request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(request as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw Failure(status: status) }
  }

  func remove(id: UUID) throws {
    let status = SecItemDelete(query(id: id) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Failure(status: status)
    }
  }
}
