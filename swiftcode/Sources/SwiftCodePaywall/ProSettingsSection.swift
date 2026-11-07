import Foundation

public struct ProSectionState: Equatable, Sendable {
    public var isPro: Bool
    public var source: ProAccessSource

    public init(entitlement: PaywallEntitlementState) {
        self.isPro = entitlement.isPro
        self.source = entitlement.source
    }

    public init(isPro: Bool, source: ProAccessSource) {
        self.isPro = isPro
        self.source = source
    }

    public var memberTitle: String { "SwiftCode Pro Member!" }

    public var statusText: String? { isPro ? "Active" : nil }

    public var upgradeTitle: String { "Upgrade to Pro" }

    public var showsUpgradeButton: Bool { !isPro }
}

#if canImport(SwiftUI)
import SwiftUI

public struct ProSettingsSection: View {
    private let store: PaywallStore
    @State private var state = ProSectionState(isPro: false, source: .none)
    @State private var showingPaywall = false

    public init(store: PaywallStore = .shared) {
        self.store = store
    }

    public var body: some View {
        Group {
            if state.isPro {
                HStack {
                    Label(state.memberTitle, systemImage: "crown.fill")
                    Spacer()
                    if let status = state.statusText {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            } else {
                Button(state.upgradeTitle) {
                    showingPaywall = true
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(store: store)
        }
        .task {
            await store.refreshEntitlements()
            store.refreshBypassFlag()
            state = ProSectionState(entitlement: store.entitlement)
        }
    }
}
#endif
