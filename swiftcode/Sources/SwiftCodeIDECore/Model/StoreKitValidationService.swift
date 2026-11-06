// Ported from Legacy `SwiftCode/Views/Utilities/StoreKit/Services/StoreKitValidationService.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: ValidationIssue, StoreKitValidationService.
//
// CLEANUP (2026-11-06, triage §C21) — `checkIAPCapabilityEnabled()` and
// `checkAppSandboxConfigured()` used to unconditionally return `true`
// ("mock validation for sandboxed development environment consistency"),
// so validation could never flag a missing capability. They now inspect
// the active project's real `.entitlements` files: IAP is enabled when
// any of them contains `com.apple.developer.in-app-payments`; the sandbox
// is configured when any sets `com.apple.security.app-sandbox` to true.
// No active project, or no `.entitlements` file found, reports `false`
// (capability not present, not assumed). Only `.entitlements` files
// inside the active project's directory tree are scanned; a
// `CODE_SIGN_ENTITLEMENTS` path pointing outside the tree is not
// followed.

import Foundation

public struct ValidationIssue: Identifiable, Sendable {
    public var id = UUID()
    public var severity: Severity
    public var category: Category
    public var message: String
    public var objectID: String? // Related Product ID, etc.
    public var fixType: ValidationFixType?

    public enum Severity: String, Codable, Sendable {
        case error = "Error"
        case warning = "Warning"
        case suggestion = "Suggestion"
        case optimization = "Optimization"
    }

    public enum Category: String, Codable, Sendable {
        case schema = "Schema"
        case identifier = "Identifier"
        case localization = "Localization"
        case relationship = "Relationship"
        case configuration = "Configuration"
        case capability = "Capability"
    }

    public enum ValidationFixType: String, Codable, Sendable {
        case generateMissingLocalization = "Generate Missing English Localization"
        case fixNegativePrice = "Set Price to Default ($0.99)"
        case fixEmptyIdentifier = "Generate Unique Product ID"
        case fixDuplicateIdentifier = "Rename Identifier to Unique"
        case fixMismatchGroup = "Re-align Group ID"
        case installSandboxCapability = "Provision App Sandbox Entitlement"
        case installIAPCapability = "Enable In-App Purchase Capability"
    }
}

public final class StoreKitValidationService: Sendable {
    public static let shared = StoreKitValidationService()

    private init() {}

    public func calculateHealthScore(issues: [ValidationIssue]) -> Int {
        var score = 100
        for issue in issues {
            switch issue.severity {
            case .error:
                score -= 15
            case .warning:
                score -= 8
            case .suggestion:
                score -= 3
            case .optimization:
                score -= 1
            }
        }
        return max(0, min(100, score))
    }

    public func validate(config: StoreKitConfig) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        var productIDs = Set<String>()
        var referenceNames = Set<String>()

        // 1. Validate Capability & Sandbox Setup (Dynamic project-level scanner)
        let hasIAP = checkIAPCapabilityEnabled()
        if !hasIAP {
            issues.append(ValidationIssue(
                severity: .warning,
                category: .capability,
                message: "Missing In-App Purchase capability inside active project entitlements.",
                objectID: "project_capabilities",
                fixType: .installIAPCapability
            ))
        }

        let hasSandbox = checkAppSandboxConfigured()
        if !hasSandbox {
            issues.append(ValidationIssue(
                severity: .warning,
                category: .capability,
                message: "Missing App Sandbox configurations inside project entitlements plist.",
                objectID: "sandbox_capabilities",
                fixType: .installSandboxCapability
            ))
        }

        // 2. Validate Standard Products
        for product in config.products {
            // Check Empty IDs
            if product.productID.isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    category: .identifier,
                    message: "Product reference '\(product.referenceName)' has an empty Product Identifier.",
                    objectID: product.productID,
                    fixType: .fixEmptyIdentifier
                ))
            } else {
                if productIDs.contains(product.productID) {
                    issues.append(ValidationIssue(
                        severity: .error,
                        category: .identifier,
                        message: "Duplicate Product Identifier found: '\(product.productID)'.",
                        objectID: product.productID,
                        fixType: .fixDuplicateIdentifier
                    ))
                }
                productIDs.insert(product.productID)
            }

            // Check Duplicate Reference Names
            if product.referenceName.isEmpty {
                issues.append(ValidationIssue(
                    severity: .warning,
                    category: .configuration,
                    message: "Product with ID '\(product.productID)' has an empty reference name.",
                    objectID: product.productID
                ))
            } else {
                if referenceNames.contains(product.referenceName) {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        category: .configuration,
                        message: "Duplicate reference name found: '\(product.referenceName)'.",
                        objectID: product.productID
                    ))
                }
                referenceNames.insert(product.referenceName)
            }

            // Check Price
            if product.price < 0 {
                issues.append(ValidationIssue(
                    severity: .error,
                    category: .configuration,
                    message: "Product '\(product.referenceName)' has a negative price (\(product.price)).",
                    objectID: product.productID,
                    fixType: .fixNegativePrice
                ))
            }

            // Validate Localizations
            if product.localizations.isEmpty {
                issues.append(ValidationIssue(
                    severity: .warning,
                    category: .localization,
                    message: "Product '\(product.referenceName)' has no localizations added.",
                    objectID: product.productID,
                    fixType: .generateMissingLocalization
                ))
            } else {
                for loc in product.localizations {
                    if loc.displayName.isEmpty {
                        issues.append(ValidationIssue(
                            severity: .error,
                            category: .localization,
                            message: "Missing Display Name for locale '\(loc.locale)' in product '\(product.referenceName)'.",
                            objectID: product.productID,
                            fixType: .generateMissingLocalization
                        ))
                    }
                    if loc.description.isEmpty {
                        issues.append(ValidationIssue(
                            severity: .warning,
                            category: .localization,
                            message: "Missing Description for locale '\(loc.locale)' in product '\(product.referenceName)'.",
                            objectID: product.productID,
                            fixType: .generateMissingLocalization
                        ))
                    }
                }
            }
        }

        // 3. Validate Non-Renewing Subscriptions
        for sub in config.nonRenewingSubscriptions {
            if sub.productID.isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    category: .identifier,
                    message: "Non-Renewing Subscription reference '\(sub.referenceName)' has an empty Product Identifier.",
                    objectID: sub.productID,
                    fixType: .fixEmptyIdentifier
                ))
            } else {
                if productIDs.contains(sub.productID) {
                    issues.append(ValidationIssue(
                        severity: .error,
                        category: .identifier,
                        message: "Duplicate Identifier found in non-renewing subscription: '\(sub.productID)'.",
                        objectID: sub.productID,
                        fixType: .fixDuplicateIdentifier
                    ))
                }
                productIDs.insert(sub.productID)
            }

            if sub.price < 0 {
                issues.append(ValidationIssue(
                    severity: .error,
                    category: .configuration,
                    message: "Non-renewing subscription '\(sub.referenceName)' has a negative price.",
                    objectID: sub.productID,
                    fixType: .fixNegativePrice
                ))
            }

            if sub.localizations.isEmpty {
                issues.append(ValidationIssue(
                    severity: .warning,
                    category: .localization,
                    message: "Non-renewing subscription '\(sub.referenceName)' has no localizations.",
                    objectID: sub.productID,
                    fixType: .generateMissingLocalization
                ))
            }
        }

        // 4. Validate Subscription Groups & Subscriptions
        for group in config.subscriptionGroups {
            if group.groupName.isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    category: .configuration,
                    message: "A subscription group has an empty group name.",
                    objectID: group.groupName
                ))
            }

            if group.subscriptions.isEmpty {
                issues.append(ValidationIssue(
                    severity: .suggestion,
                    category: .configuration,
                    message: "Subscription group '\(group.groupName)' contains no auto-renewable subscriptions.",
                    objectID: group.groupName
                ))
            }

            for sub in group.subscriptions {
                if sub.productID.isEmpty {
                    issues.append(ValidationIssue(
                        severity: .error,
                        category: .identifier,
                        message: "Auto-renewing subscription reference '\(sub.referenceName)' has an empty Product Identifier.",
                        objectID: sub.productID,
                        fixType: .fixEmptyIdentifier
                    ))
                } else {
                    if productIDs.contains(sub.productID) {
                        issues.append(ValidationIssue(
                            severity: .error,
                            category: .identifier,
                            message: "Duplicate Identifier found in subscription '\(sub.productID)'.",
                            objectID: sub.productID,
                            fixType: .fixDuplicateIdentifier
                        ))
                    }
                    productIDs.insert(sub.productID)
                }

                if sub.subscriptionGroupID != group.groupName {
                    issues.append(ValidationIssue(
                        severity: .error,
                        category: .relationship,
                        message: "Subscription '\(sub.referenceName)' has mismatching group ID: expected '\(group.groupName)' but got '\(sub.subscriptionGroupID)'.",
                        objectID: sub.productID,
                        fixType: .fixMismatchGroup
                    ))
                }

                // Check Period
                let validPeriods = ["P1W", "P1M", "P2M", "P3M", "P6M", "P1Y"]
                if !validPeriods.contains(sub.subscriptionPeriod) {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        category: .configuration,
                        message: "Subscription '\(sub.referenceName)' has non-standard duration period '\(sub.subscriptionPeriod)'. Standard durations are P1W, P1M, P2M, P3M, P6M, P1Y.",
                        objectID: sub.productID
                    ))
                }

                // Intro offers
                for intro in sub.introductoryOffers {
                    if intro.price < 0 {
                        issues.append(ValidationIssue(
                            severity: .error,
                            category: .configuration,
                            message: "Introductory Offer for '\(sub.referenceName)' has negative price.",
                            objectID: sub.productID,
                            fixType: .fixNegativePrice
                        ))
                    }
                }

                // Promotional offers
                var offerIDs = Set<String>()
                for promo in sub.promotionalOffers {
                    if promo.offerID.isEmpty {
                        issues.append(ValidationIssue(
                            severity: .error,
                            category: .identifier,
                            message: "Promotional Offer in '\(sub.referenceName)' has an empty offer ID.",
                            objectID: sub.productID
                        ))
                    } else {
                        if offerIDs.contains(promo.offerID) {
                            issues.append(ValidationIssue(
                                severity: .error,
                                category: .identifier,
                                message: "Duplicate Offer ID '\(promo.offerID)' in subscription '\(sub.referenceName)'.",
                                objectID: sub.productID
                            ))
                        }
                        offerIDs.insert(promo.offerID)
                    }
                }
            }
        }

        return issues
    }

    // Capability checks — real inspection of the active project's
    // `.entitlements` files (see header). IAP is enabled when any
    // `.entitlements` file in the active project contains the
    // `com.apple.developer.in-app-payments` key (the key Xcode writes
    // when the capability is enabled); the sandbox is configured when
    // any such file sets `com.apple.security.app-sandbox` to true.
    private func checkIAPCapabilityEnabled() -> Bool {
        activeProjectEntitlementKeys().contains("com.apple.developer.in-app-payments")
    }

    private func checkAppSandboxConfigured() -> Bool {
        activeProjectEntitlementKeys().contains("com.apple.security.app-sandbox")
    }

    /// Entitlement keys set to a truthy value in the active project's
    /// `.entitlements` files. Empty when there is no active project, no
    /// `.entitlements` file is found, or this runs off the main thread
    /// (the session store is `@MainActor`, and validation is invoked
    /// from the StoreKit UI, which runs on the main thread).
    private func activeProjectEntitlementKeys() -> Set<String> {
        guard Thread.isMainThread else { return [] }
        return MainActor.assumeIsolated {
            guard let directory = ProjectSessionStore.shared.activeProject?.directoryURL else { return Set<String>() }
            var keys = Set<String>()
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension == "entitlements",
                      let data = try? Data(contentsOf: fileURL),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { continue }
                for (key, value) in plist where Self.isTruthyEntitlementValue(value) {
                    keys.insert(key)
                }
            }
            return keys
        }
    }

    /// An entitlement value that means "enabled": `true`, a non-zero
    /// number, or a non-empty string/array/dictionary. (The IAP key, for
    /// example, carries a merchant-ID array rather than a bool.)
    private static func isTruthyEntitlementValue(_ value: Any) -> Bool {
        switch value {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.boolValue
        case let string as String: return !string.isEmpty
        case let array as [Any]: return !array.isEmpty
        case let dict as [String: Any]: return !dict.isEmpty
        default: return false
        }
    }
}
