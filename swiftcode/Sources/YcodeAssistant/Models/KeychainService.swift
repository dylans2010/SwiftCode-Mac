import Foundation

public final class KeychainService: @unchecked Sendable {
  public static let shared = KeychainService()

  private let lock = NSLock()
  private var memoryFallback: [String: String] = [:]
  private let fallbackPrefix = "com.swiftcode.fallback.key."

  private var cacheFileURL: URL? {
    let fm = FileManager.default
    guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }
    let dir = appSupport.appendingPathComponent("com.swiftcode.app", isDirectory: true)
    if !fm.fileExists(atPath: dir.path) {
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir.appendingPathComponent("secure_credentials_cache.json")
  }

  private init() {
    loadCachedCredentials()
  }

  private func loadCachedCredentials() {
    lock.lock()
    defer { lock.unlock() }

    if let fileURL = cacheFileURL,
       let data = try? Data(contentsOf: fileURL),
       let dict = try? JSONDecoder().decode([String: String].self, from: data) {
      for (k, v) in dict {
        memoryFallback[k] = v
      }
    }

    let allDefaults = UserDefaults.standard.dictionaryRepresentation()
    for (k, v) in allDefaults where k.hasPrefix(fallbackPrefix) {
      let rawKey = String(k.dropFirst(fallbackPrefix.count))
      if memoryFallback[rawKey] == nil,
         let base64 = v as? String,
         let data = Data(base64Encoded: base64),
         let decoded = String(data: data, encoding: .utf8) {
        memoryFallback[rawKey] = decoded
      }
    }
  }

  private func persistToFileLocked() {
    guard let fileURL = cacheFileURL else { return }
    if let data = try? JSONEncoder().encode(memoryFallback) {
      try? data.write(to: fileURL, options: .atomic)
    }
  }

  @discardableResult
  public func set(_ value: String, forKey key: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }

    memoryFallback[key] = value

    if let data = value.data(using: .utf8) {
      let base64 = data.base64EncodedString()
      UserDefaults.standard.set(base64, forKey: fallbackPrefix + key)
    }

    persistToFileLocked()
    return true
  }

  public func get(forKey key: String) -> String? {
    lock.lock()
    defer { lock.unlock() }

    if let cached = memoryFallback[key] {
      return cached
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
    lock.lock()
    defer { lock.unlock() }

    memoryFallback.removeValue(forKey: key)
    UserDefaults.standard.removeObject(forKey: fallbackPrefix + key)
    persistToFileLocked()
    return true
  }

  public func clearAllCredentials() {
    lock.lock()
    defer { lock.unlock() }

    memoryFallback.removeAll()

    let allDefaults = UserDefaults.standard.dictionaryRepresentation()
    for (k, _) in allDefaults where k.hasPrefix(fallbackPrefix) {
      UserDefaults.standard.removeObject(forKey: k)
    }

    if let fileURL = cacheFileURL {
      try? FileManager.default.removeItem(at: fileURL)
    }
  }

  public func contains(key: String) -> Bool {
    get(forKey: key) != nil
  }

  public func save(account: String, value: String) throws {
    guard set(value, forKey: account) else {
      throw NSError(domain: "KeychainService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to save credentials"])
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
  public static let composioAPIKey = "composio_api_key"
  public static let googleOAuthAccessToken = "google_oauth_access_token"
  public static let googleOAuthRefreshToken = "google_oauth_refresh_token"
  public static let googleAccountEmail = "google_account_email"
  public static let googleOAuthExpiresAt = "google_oauth_expires_at"
}
