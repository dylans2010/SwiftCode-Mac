import Foundation
import Security

public final class KeychainService: @unchecked Sendable {
  public static let shared = KeychainService()

  private let service = "com.swiftcode.app"

  private init() {}

  @discardableResult
  public func set(_ value: String, forKey key: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }

    delete(forKey: key)

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]

    let status = SecItemAdd(query as CFDictionary, nil)
    return status == errSecSuccess
  }

  public func get(forKey key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  @discardableResult
  public func delete(forKey key: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]

    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  public func contains(key: String) -> Bool {
    get(forKey: key) != nil
  }

  public func save(account: String, value: String) throws {
    guard set(value, forKey: account) else {
      throw AppError.securityError("Failed to save to keychain")
    }
  }

  public func get(account: String) throws -> String? {
    get(forKey: account)
  }
}

extension KeychainService {
  public static let openRouterAPIKey = "openrouter_api_key"
  public static let githubToken = "github_personal_access_token"
  public static let codexUserAPIKey = "codex_user_api_key"
  public static let codexAppAPIKey = "codex_app_api_key"
}
