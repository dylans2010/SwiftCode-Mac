import Foundation
import Security

public final class KeychainService: @unchecked Sendable {
  public static let shared = KeychainService()

  private let service = "com.swiftcode.app"
  private var memoryFallback: [String: String] = [:]
  private let fallbackPrefix = "com.swiftcode.fallback.key."

  private init() {}

  @discardableResult
  public func set(_ value: String, forKey key: String) -> Bool {
    memoryFallback[key] = value

    if let data = value.data(using: .utf8) {
      let base64 = data.base64EncodedString()
      UserDefaults.standard.set(base64, forKey: fallbackPrefix + key)
    }

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
    if let cached = memoryFallback[key] {
      return cached
    }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    if status == errSecSuccess,
      let data = result as? Data {
      let value = String(data: data, encoding: .utf8)
      if let val = value {
        memoryFallback[key] = val
        return val
      }
    }

    if let base64 = UserDefaults.standard.string(forKey: fallbackPrefix + key),
       let data = Data(base64Encoded: base64),
       let value = String(data: data, encoding: .utf8) {
      memoryFallback[key] = value
      return value
    }

    return nil
  }

  @discardableResult
  public func delete(forKey key: String) -> Bool {
    memoryFallback.removeValue(forKey: key)
    UserDefaults.standard.removeObject(forKey: fallbackPrefix + key)

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
