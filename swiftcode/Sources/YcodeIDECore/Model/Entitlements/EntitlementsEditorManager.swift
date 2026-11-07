import Foundation
import os

public final class EntitlementsEditorManager: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func readEntitlements() throws -> [String: Any] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else {
            logger.info("Entitlements file not found at \(self.fileURL.path). Returning empty template.")
            return [:]
        }
        let data = try Data(contentsOf: fileURL)
        if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return plist
        }
        return [:]
    }

    public func writeEntitlements(_ entitlements: [String: Any]) throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
            throw NSError(domain: "EntitlementsEditorManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "The target path is a directory, not an entitlements file: \(fileURL.lastPathComponent)"])
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let sorted = sortDictionary(entitlements)
        let data = try PropertyListSerialization.data(fromPropertyList: sorted, format: .xml, options: 0)
        try data.write(to: fileURL, options: .atomic)
        logger.info("Successfully wrote entitlements plist at \(self.fileURL.path).")
    }

    private func sortDictionary(_ dict: [String: Any]) -> [String: Any] {
        var sorted: [String: Any] = [:]
        for key in dict.keys.sorted() {
            if let valDict = dict[key] as? [String: Any] {
                sorted[key] = sortDictionary(valDict)
            } else if let valArray = dict[key] as? [[String: Any]] {
                sorted[key] = valArray.map { sortDictionary($0) }
            } else {
                sorted[key] = dict[key]
            }
        }
        return sorted
    }

    public func validate(_ entitlements: [String: Any]) -> EntitlementValidationResult {
        var warnings: [EntitlementWarning] = []
        var errors: [EntitlementError] = []

        if let sandboxVal = entitlements["com.apple.security.app-sandbox"] as? Bool {
            if !sandboxVal {
                warnings.append(EntitlementWarning(
                    rawKey: "com.apple.security.app-sandbox",
                    message: "App Sandbox is disabled. This will prevent App Store distribution."
                ))
            }
        } else {
            warnings.append(EntitlementWarning(
                rawKey: "com.apple.security.app-sandbox",
                message: "App Sandbox entitlement is missing entirely."
            ))
        }

        let hasNetwork = entitlements["com.apple.security.network.client"] as? Bool ?? false
        let hasSandbox = entitlements["com.apple.security.app-sandbox"] as? Bool ?? false
        if hasNetwork && !hasSandbox {
            warnings.append(EntitlementWarning(
                rawKey: "com.apple.security.network.client",
                message: "Network Client outgoing connections are enabled, but App Sandbox is inactive."
            ))
        }

        if let groups = entitlements["com.apple.security.application-groups"] {
            if !(groups is [String]) {
                errors.append(EntitlementError(
                    rawKey: "com.apple.security.application-groups",
                    message: "App Groups entitlement must be an array of strings."
                ))
            }
        }

        let isValid = errors.isEmpty
        return EntitlementValidationResult(isValid: isValid, warnings: warnings, errors: errors)
    }

    public func crossEntitlementIssues(_ entitlements: [String: Any]) -> EntitlementValidationResult {
        var warnings: [EntitlementWarning] = []
        var errors: [EntitlementError] = []

        let sandbox = entitlements["com.apple.security.app-sandbox"] as? Bool ?? false

        if let aps = entitlements["aps-environment"] {
            if let value = aps as? String, value == "development" || value == "production" {
            } else {
                errors.append(EntitlementError(
                    rawKey: "aps-environment",
                    message: "aps-environment must be \"development\" or \"production\"."
                ))
            }
        }

        if !sandbox {
            for key in ["com.apple.security.network.client", "com.apple.security.network.server"] {
                if entitlements[key] != nil {
                    warnings.append(EntitlementWarning(
                        rawKey: key,
                        message: "This entitlement is set but App Sandbox is off; sandbox resource entitlements have no effect without it."
                    ))
                }
            }
        }

        for key in [
            "com.apple.security.device.camera",
            "com.apple.security.device.audio-input",
            "com.apple.security.personal-information.photos-library",
            "com.apple.security.personal-information.location"
        ] where entitlements[key] != nil && !sandbox {
            warnings.append(EntitlementWarning(
                rawKey: key,
                message: "This entitlement only takes effect in a sandboxed app, but App Sandbox is off."
            ))
        }

        let folderPairs = [
            ("com.apple.security.files.user-selected.read-only", "com.apple.security.files.user-selected.read-write"),
            ("com.apple.security.assets.downloads.read-only", "com.apple.security.assets.downloads.read-write"),
            ("com.apple.security.assets.pictures.read-only", "com.apple.security.assets.pictures.read-write"),
            ("com.apple.security.assets.music.read-only", "com.apple.security.assets.music.read-write"),
            ("com.apple.security.assets.movies.read-only", "com.apple.security.assets.movies.read-write")
        ]
        for (readOnly, readWrite) in folderPairs
            where entitlements[readOnly] != nil && entitlements[readWrite] != nil {
            warnings.append(EntitlementWarning(
                rawKey: readOnly,
                message: "Read-write access already includes read access; the read-only key for this folder is redundant."
            ))
        }

        let csKeys = [
            "com.apple.security.cs.allow-jit",
            "com.apple.security.cs.allow-unsigned-executable-memory",
            "com.apple.security.cs.disable-library-validation",
            "com.apple.security.cs.allow-dyld-environment-variables",
            "com.apple.security.cs.debugger"
        ]
        if sandbox, csKeys.contains(where: { entitlements[$0] != nil }) {
            warnings.append(EntitlementWarning(
                rawKey: "com.apple.security.cs.*",
                message: "Hardened Runtime entitlements apply to Developer ID / notarized distribution; Mac App Store builds enforce their own runtime policy."
            ))
        }

        let containers = entitlements["com.apple.developer.icloud-container-identifiers"]
        let services = entitlements["com.apple.developer.icloud-services"] as? [String]
        if containers != nil && (services?.isEmpty ?? true) {
            warnings.append(EntitlementWarning(
                rawKey: "com.apple.developer.icloud-container-identifiers",
                message: "iCloud container identifiers are set but no iCloud services (CloudDocuments / CloudKit) are enabled."
            ))
        }
        if let services, !services.isEmpty, containers == nil {
            warnings.append(EntitlementWarning(
                rawKey: "com.apple.developer.icloud-services",
                message: "iCloud services are enabled but no container identifiers are set."
            ))
        }
        if entitlements["NSUbiquitousContainers"] != nil && containers == nil {
            warnings.append(EntitlementWarning(
                rawKey: "NSUbiquitousContainers",
                message: "Ubiquitous containers are declared but no iCloud container identifiers are set."
            ))
        }

        if let groups = entitlements["com.apple.security.application-groups"] {
            if let arr = groups as? [String] {
                if arr.isEmpty {
                    warnings.append(EntitlementWarning(
                        rawKey: "com.apple.security.application-groups",
                        message: "App Groups is enabled with an empty identifier list."
                    ))
                } else if arr.contains(where: { !$0.hasPrefix("group.") }) {
                    warnings.append(EntitlementWarning(
                        rawKey: "com.apple.security.application-groups",
                        message: "App Group identifiers should begin with \"group.\"."
                    ))
                }
            } else {
                errors.append(EntitlementError(
                    rawKey: "com.apple.security.application-groups",
                    message: "App Groups must be an array of strings."
                ))
            }
        }

        if let keychain = entitlements["keychain-access-groups"] {
            if let arr = keychain as? [String] {
                if arr.isEmpty {
                    warnings.append(EntitlementWarning(
                        rawKey: "keychain-access-groups",
                        message: "Keychain Access Groups is enabled with an empty identifier list."
                    ))
                }
            } else {
                errors.append(EntitlementError(
                    rawKey: "keychain-access-groups",
                    message: "Keychain Access Groups must be an array of strings."
                ))
            }
        }

        let knownPrefixes = ["applinks:", "webcredentials:", "activitycontinuation:", "appclips:"]
        if let domains = entitlements["com.apple.developer.associated-domains"] as? [String] {
            let bad = domains.filter { domain in !knownPrefixes.contains(where: domain.hasPrefix) }
            if !bad.isEmpty {
                warnings.append(EntitlementWarning(
                    rawKey: "com.apple.developer.associated-domains",
                    message: "Entries should begin with one of applinks:, webcredentials:, activitycontinuation:, appclips:."
                ))
            }
        }

        let validDDP = [
            "NSFileProtectionComplete",
            "NSFileProtectionCompleteUnlessOpen",
            "NSFileProtectionCompleteUntilFirstUserAuthentication",
            "NSFileProtectionNone"
        ]
        if let ddp = entitlements["com.apple.developer.default-data-protection"] as? String,
           !validDDP.contains(ddp) {
            errors.append(EntitlementError(
                rawKey: "com.apple.developer.default-data-protection",
                message: "Unknown data protection class. Use one of the NSFileProtection values."
            ))
        }

        if entitlements["com.apple.security.network.server"] as? Bool == true {
            warnings.append(EntitlementWarning(
                rawKey: "com.apple.security.network.server",
                message: "Incoming network connections may draw extra App Review scrutiny; be ready to explain why the app listens."
            ))
        }

        for key in [
            "com.apple.developer.driverkit",
            "com.apple.developer.endpoint-security.client",
            "com.apple.developer.networking.networkextension",
            "com.apple.developer.system-extension.install"
        ] where entitlements[key] != nil {
            warnings.append(EntitlementWarning(
                rawKey: key,
                message: "Requires a special entitlement request to Apple — the key alone does not grant access."
            ))
        }

        return EntitlementValidationResult(isValid: errors.isEmpty, warnings: warnings, errors: errors)
    }

    public func generateRawXML(_ entitlements: [String: Any]) -> String {
        let sorted = sortDictionary(entitlements)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: sorted, format: .xml, options: 0),
              let xmlString = String(data: data, encoding: .utf8) else {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<dict>\n</dict>\n</plist>"
        }
        return xmlString
    }

    public func parseRawXML(_ xml: String) throws -> [String: Any] {
        guard let data = xml.data(using: .utf8) else {
            throw NSError(domain: "EntitlementsEditorManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 encoding"])
        }
        if let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return dict
        }
        throw NSError(domain: "EntitlementsEditorManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "XML plist is not a valid dictionary."])
    }
}
