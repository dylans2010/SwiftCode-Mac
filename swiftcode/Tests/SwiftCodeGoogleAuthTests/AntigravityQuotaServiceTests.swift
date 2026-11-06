// Tests for AntigravityQuotaService (Legacy -> SwiftCodeGoogleAuth port).
// Static only: not executed here (no Swift toolchain in this environment).
// The service persists quota windows in UserDefaults; each test resets the
// service to fresh state first and last so no quota state leaks between runs.

import Foundation
import Testing
@testable import SwiftCodeGoogleAuth

@Suite("AntigravityQuotaService", .serialized)
struct AntigravityQuotaServiceTests {

    @Test("Plan tiers carry Legacy's limits")
    func planTierLimits() {
        #expect(AntigravityPlanTier.plus.fiveHourLimit == 40)
        #expect(AntigravityPlanTier.plus.weeklyLimit == 300)
        #expect(AntigravityPlanTier.pro.fiveHourLimit == 100)
        #expect(AntigravityPlanTier.pro.weeklyLimit == 1000)
        #expect(AntigravityPlanTier.ultra.fiveHourLimit == 250)
        #expect(AntigravityPlanTier.ultra.weeklyLimit == 3000)
    }

    @Test("Gauge hex thresholds: green >= 60%, yellow 21-59%, red <= 20%")
    func gaugeHexThresholds() {
        #expect(AntigravityQuotaService.gaugeColorHex(forPercentage: 100) == "#34C759")
        #expect(AntigravityQuotaService.gaugeColorHex(forPercentage: 60) == "#34C759")
        #expect(AntigravityQuotaService.gaugeColorHex(forPercentage: 59) == "#FFCC00")
        #expect(AntigravityQuotaService.gaugeColorHex(forPercentage: 21) == "#FFCC00")
        #expect(AntigravityQuotaService.gaugeColorHex(forPercentage: 20) == "#FF3B30")
        #expect(AntigravityQuotaService.gaugeColorHex(forPercentage: 0) == "#FF3B30")
    }

    @Test("recordRequest advances usage and resetToFresh restores it")
    @MainActor
    func recordAndReset() {
        let service = AntigravityQuotaService.shared
        service.resetToFresh()
        #expect(service.fiveHourUsed == 0)
        #expect(service.weeklyUsed == 0)
        service.recordRequest()
        #expect(service.fiveHourUsed == 1)
        #expect(service.weeklyUsed == 1)
        service.resetToFresh()
        #expect(service.fiveHourUsed == 0)
        #expect(service.weeklyUsed == 0)
    }

    @Test("Gradient hex colours exist per tier (no SwiftUI dependency)")
    func gradientHexColors() {
        #expect(AntigravityPlanTier.plus.gradientHexColors.count == 2)
        #expect(AntigravityPlanTier.pro.gradientHexColors.count == 2)
        #expect(AntigravityPlanTier.ultra.gradientHexColors.count == 2)
        for tier in AntigravityPlanTier.allCases {
            #expect(tier.gradientHexColors.allSatisfy { $0.hasPrefix("#") && $0.count == 7 })
        }
    }
}
