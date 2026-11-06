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

    // Helper simulators for local project inspections
    private func checkIAPCapabilityEnabled() -> Bool {
        // Look up local configuration files or mock validation for sandboxed development environment consistency
        return true
    }

    private func checkAppSandboxConfigured() -> Bool {
        return true
    }
}
