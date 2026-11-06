import Foundation

// MARK: - Settings Pro section (Wave 15)
//
// The Settings Pro section (Legacy
// `SwiftCode/Views/Settings/GeneralSettingsView.swift:1880-1896`
// `proSection`): the IDE's ONLY production Pro gate. If the user
// is Pro, it shows the member line; otherwise an "Upgrade to Pro"
// button that presents the paywall. The six features listed on
// the paywall are not gated anywhere in Legacy, and no gate is
// invented here — this section presents the paywall and shows
// Pro status, nothing more.
//
// SwiftCode style, not Legacy's: no orange accent, no capitalised
// headers, sentence-case copy. The AppKit Settings pane
// (`SwiftCodeUI` `GeneralSettingsPane`) builds this section from
// `ProSectionState`; the SwiftUI `ProSettingsSection` view below
// is the same section for SwiftUI hosts. The entitlement rule
// is Wave 13's `PaywallEntitlementState`: Pro iff any verified
// current entitlement exists OR the `bypass_paywall` developer
// flag is on (a debug override wins when set).

/// The Pro section's state, derived from the entitlement state.
/// Pure and testable without StoreKit.
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

    /// Legacy's member line, without the orange tint.
    public var memberTitle: String { "SwiftCode Pro Member!" }

    /// Legacy's status text for members.
    public var statusText: String? { isPro ? "Active" : nil }

    /// Legacy's upgrade button title.
    public var upgradeTitle: String { "Upgrade to Pro" }

    /// Whether the section shows the upgrade button (not Pro).
    public var showsUpgradeButton: Bool { !isPro }
}

#if canImport(SwiftUI)
import SwiftUI

/// The Settings Pro section as a SwiftUI view: the member line
/// for Pro users, otherwise an "Upgrade to Pro" button that
/// presents the Wave 13 paywall as a sheet.
///
/// The view snapshots the store into `@State` and re-syncs after
/// every action (the store is not an `ObservableObject` — this
/// target compiles on Linux, where Combine does not exist), the
/// same pattern as `PaywallView`. It refreshes entitlements and
/// the bypass flag on appear so the section reflects a purchase
/// made since Settings was opened.
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
