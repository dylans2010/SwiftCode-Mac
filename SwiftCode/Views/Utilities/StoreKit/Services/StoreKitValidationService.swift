import Foundation

public struct ValidationIssue: Identifiable, Sendable {
    public var id = UUID()
    public var severity: Severity
    public var category: Category
    public var message: String
    public var objectID: String? // Related Product ID, etc.

    public enum Severity: String, Codable, Sendable {
        case error = "Error"
        case warning = "Warning"
        case suggestion = "Suggestion"
    }

    public enum Category: String, Codable, Sendable {
        case schema = "Schema"
        case identifier = "Identifier"
        case localization = "Localization"
        case relationship = "Relationship"
        case configuration = "Configuration"
    }
}

public final class StoreKitValidationService: Sendable {
    public static let shared = StoreKitValidationService()

    private init() {}

    public func validate(config: StoreKitConfig) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        var productIDs = Set<String>()
        var referenceNames = Set<String>()

        // 1. Validate Standard Products
        for product in config.products {
            // Check Empty IDs
            if product.productID.isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    category: .identifier,
                    message: "Product reference '\(product.referenceName)' has an empty Product Identifier.",
                    objectID: product.productID
                ))
            } else {
                if productIDs.contains(product.productID) {
                    issues.append(ValidationIssue(
                        severity: .error,
                        category: .identifier,
                        message: "Duplicate Product Identifier found: '\(product.productID)'.",
                        objectID: product.productID
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
                    objectID: product.productID
                ))
            }

            // Validate Localizations
            if product.localizations.isEmpty {
                issues.append(ValidationIssue(
                    severity: .warning,
                    category: .localization,
                    message: "Product '\(product.referenceName)' has no localizations added.",
                    objectID: product.productID
                ))
            } else {
                for loc in product.localizations {
                    if loc.displayName.isEmpty {
                        issues.append(ValidationIssue(
                            severity: .error,
                            category: .localization,
                            message: "Missing Display Name for locale '\(loc.locale)' in product '\(product.referenceName)'.",
                            objectID: product.productID
                        ))
                    }
                    if loc.description.isEmpty {
                        issues.append(ValidationIssue(
                            severity: .warning,
                            category: .localization,
                            message: "Missing Description for locale '\(loc.locale)' in product '\(product.referenceName)'.",
                            objectID: product.productID
                        ))
                    }
                }
            }
        }

        // 2. Validate Non-Renewing Subscriptions
        for sub in config.nonRenewingSubscriptions {
            if sub.productID.isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    category: .identifier,
                    message: "Non-Renewing Subscription reference '\(sub.referenceName)' has an empty Product Identifier.",
                    objectID: sub.productID
                ))
            } else {
                if productIDs.contains(sub.productID) {
                    issues.append(ValidationIssue(
                        severity: .error,
                        category: .identifier,
                        message: "Duplicate Identifier found in non-renewing subscription: '\(sub.productID)'.",
                        objectID: sub.productID
                    ))
                }
                productIDs.insert(sub.productID)
            }

            if sub.price < 0 {
                issues.append(ValidationIssue(
                    severity: .error,
                    category: .configuration,
                    message: "Non-renewing subscription '\(sub.referenceName)' has a negative price.",
                    objectID: sub.productID
                ))
            }

            if sub.localizations.isEmpty {
                issues.append(ValidationIssue(
                    severity: .warning,
                    category: .localization,
                    message: "Non-renewing subscription '\(sub.referenceName)' has no localizations.",
                    objectID: sub.productID
                ))
            }
        }

        // 3. Validate Subscription Groups & Subscriptions
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
                        objectID: sub.productID
                    ))
                } else {
                    if productIDs.contains(sub.productID) {
                        issues.append(ValidationIssue(
                            severity: .error,
                            category: .identifier,
                            message: "Duplicate Identifier found in subscription '\(sub.productID)'.",
                            objectID: sub.productID
                        ))
                    }
                    productIDs.insert(sub.productID)
                }

                if sub.subscriptionGroupID != group.groupName {
                    issues.append(ValidationIssue(
                        severity: .error,
                        category: .relationship,
                        message: "Subscription '\(sub.referenceName)' has mismatching group ID: expected '\(group.groupName)' but got '\(sub.subscriptionGroupID)'.",
                        objectID: sub.productID
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
                            objectID: sub.productID
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
}
