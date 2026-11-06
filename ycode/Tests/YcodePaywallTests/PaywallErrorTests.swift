import Foundation
import Testing
@testable import YcodePaywall

/// Error mapping: every case carries a message that names the cause
/// (and the fix, where there is one) and never a receipt, token, or
/// transaction secret.
struct PaywallErrorTests {

    @Test("Every error has a non-empty message")
    func allErrorsHaveMessages() {
        let errors: [PaywallError] = [
            .storeKitUnavailable,
            .productsUnavailable,
            .productFetchFailed(message: "the store was unreachable"),
            .purchaseFailed(message: "the card was declined"),
            .transactionUnverified,
            .restoreFailed(message: "the sync timed out"),
            .subscriptionsUnavailable,
        ]
        for error in errors {
            let message = error.errorDescription ?? ""
            #expect(!message.isEmpty, "Expected \(error) to have a message")
        }
    }

    @Test("StoreKit-unavailable names the missing framework")
    func storeKitUnavailableMessage() {
        #expect(PaywallError.storeKitUnavailable.errorDescription?.contains("StoreKit") == true)
        #expect(PaywallError.storeKitUnavailable.errorDescription?.contains("macOS") == true)
    }

    @Test("Unverified transactions name verification as the reason")
    func transactionUnverifiedMessage() {
        #expect(PaywallError.transactionUnverified.errorDescription?.contains("verification") == true)
        #expect(PaywallError.transactionUnverified.errorDescription?.contains("not counted") == true)
    }

    @Test("Empty product fetch points at App Store Connect")
    func productsUnavailableMessage() {
        #expect(PaywallError.productsUnavailable.errorDescription?.contains("App Store Connect") == true)
    }

    @Test("Failure messages carry the underlying reason through")
    func failureMessagesCarryReason() {
        #expect(PaywallError.productFetchFailed(message: "offline").errorDescription?.contains("offline") == true)
        #expect(PaywallError.purchaseFailed(message: "declined").errorDescription?.contains("declined") == true)
        #expect(PaywallError.restoreFailed(message: "timed out").errorDescription?.contains("timed out") == true)
    }

    @Test("Purchase outcomes distinguish success, cancel, and pending")
    func purchaseOutcomes() {
        #expect(PaywallPurchaseOutcome.purchased != .userCancelled)
        #expect(PaywallPurchaseOutcome.userCancelled != .pending)
        #expect(PaywallPurchaseOutcome.pending != .purchased)
    }
}
