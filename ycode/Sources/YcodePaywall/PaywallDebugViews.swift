#if canImport(SwiftUI)
import SwiftUI

/// The two developer debug views, ported from Legacy's
/// `PaywallDebugView` (`SwiftCode/Views/Developer/PaywallDebug/`)
/// and `StoreKitDebugView`
/// (`SwiftCode/Views/Developer/StoreKitDebug/`) and rebuilt in
/// Ycode's native style: standard `Form` sections, no `liquidGlass`.
///
/// Behaviour preserved: grant/revoke Pro, force-show the paywall,
/// and the four StoreKit simulations. What the simulations do is
/// labelled honestly here — Legacy's buttons called
/// `EntitlementManager.updateProStatus(isPro:)`, which only flipped
/// the in-memory flag; they never created a StoreKit transaction,
/// and neither do these. They set the store's debug override, which
/// the next real entitlement refresh overwrites. The views show
/// where the current Pro state comes from (`ProAccessSource`) so a
/// forced grant is never mistaken for a real purchase.
///
/// Both views snapshot the store into `@State` (the store is not an
/// `ObservableObject`, so it cannot be observed directly) and
/// re-sync after every action.
public struct PaywallDebugView: View {
    private let store: PaywallStore
    @State private var showPaywall = false
    @State private var isPro = false
    @State private var sourceText = ProAccessSource.none.rawValue

    public init(store: PaywallStore = .shared) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Pro Status Control") {
                HStack {
                    Text("Current Status:")
                    Spacer()
                    Text(isPro ? "PRO" : "FREE")
                        .bold()
                        .foregroundStyle(isPro ? .green : .orange)
                }

                HStack {
                    Text("Source:")
                    Spacer()
                    Text(sourceText)
                        .foregroundStyle(.secondary)
                }

                Button("Grant Pro Access") {
                    store.setDebugProAccess(true)
                    syncFromStore()
                }
                .foregroundStyle(.green)

                Button("Revoke Pro Access") {
                    store.setDebugProAccess(false)
                    syncFromStore()
                }
                .foregroundStyle(.red)
            } footer: {
                Text("Grant and Revoke set a debug-only override. They create no purchase and are overwritten by the next real entitlement refresh.")
            }

            Section("Presentation") {
                Button("Force Show Paywall") {
                    showPaywall = true
                }
            }
        }
        .navigationTitle("Paywall Debug")
        .sheet(isPresented: $showPaywall) {
            PaywallView(store: store)
        }
        .task { syncFromStore() }
    }

    private func syncFromStore() {
        isPro = store.isPro
        sourceText = store.entitlement.source.rawValue
    }
}

public struct StoreKitDebugView: View {
    private let store: PaywallStore
    @State private var isPro = false
    @State private var sourceText = ProAccessSource.none.rawValue
    @State private var purchasedIDs: [String] = []

    public init(store: PaywallStore = .shared) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Current Status") {
                HStack {
                    Text("Pro Status")
                    Spacer()
                    Text(isPro ? "Active" : "Inactive")
                        .foregroundColor(isPro ? .green : .red)
                }

                HStack {
                    Text("Source")
                    Spacer()
                    Text(sourceText)
                        .foregroundStyle(.secondary)
                }

                if purchasedIDs.isEmpty {
                    HStack {
                        Text("Purchased Product IDs")
                        Spacer()
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(purchasedIDs, id: \.self) { productID in
                        Text(productID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Simulations") {
                Button("Simulate Purchase Success") {
                    store.setDebugProAccess(true)
                    syncFromStore()
                }

                Button("Simulate Purchase Failure") {
                    store.setDebugProAccess(false)
                    syncFromStore()
                }

                Button("Simulate Subscription Expired") {
                    store.setDebugProAccess(false)
                    syncFromStore()
                }

                Button("Force Restore Entitlements") {
                    store.setDebugProAccess(true)
                    syncFromStore()
                }
            } footer: {
                Text("Simulations only flip the local debug override. They do not create StoreKit transactions, and the next real entitlement refresh overwrites them.")
            }
        }
        .navigationTitle("StoreKit Debug")
        .task { syncFromStore() }
    }

    private func syncFromStore() {
        isPro = store.isPro
        sourceText = store.entitlement.source.rawValue
        purchasedIDs = store.entitlement.purchasedProductIDs.sorted()
    }
}
#endif
