#if canImport(SwiftUI)
import SwiftUI

/// The SwiftCode Pro paywall, ported from Legacy's `PaywallView`
/// (`SwiftCode/Views/Paywall/PaywallView.swift`) and rebuilt in
/// Ycode's native style: standard SwiftUI controls and the default
/// accent, no `liquidGlass`, no orange tint.
///
/// Behaviour preserved from Legacy: the header, the six Pro
/// features, the live product list (name, description, localized
/// price — all from the App Store, never invented), the loading
/// state with a Refresh Products button, purchase on tap, Restore
/// Purchases, and Done to dismiss.
///
/// Deliberate differences:
/// - The store is not an `ObservableObject` (this target compiles on
///   Linux, where Combine does not exist), so the view snapshots the
///   store into `@State` and re-syncs after every action instead of
///   observing it.
/// - Purchase and restore failures are shown as text. Legacy
///   swallowed them with `try?`; a failed purchase that looks like
///   nothing happened is worse than an error message.
/// - Purchase buttons disable while a purchase is in flight, so a
///   double tap cannot start the same purchase twice.
public struct PaywallView: View {
    private let store: PaywallStore
    @Environment(\.dismiss) private var dismiss

    @State private var offers: [PaywallProductOffer] = []
    @State private var errorMessage: String?
    @State private var pendingMessage: String?
    @State private var isPurchasing = false

    public init(store: PaywallStore = .shared) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    featuresSection
                    productsSection
                    restoreButton
                }
                .padding()
            }
            .navigationTitle("SwiftCode Pro")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await store.loadProducts()
            syncFromStore()
        }
    }

    private func syncFromStore() {
        offers = store.offers
        errorMessage = store.lastError?.errorDescription
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 60))
                .padding(.bottom, 8)

            Text("Unlock Your Potential")
                .font(.title2.bold())

            Text("Upgrade to SwiftCode Pro and get access to powerful features designed for professional developers.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 20)
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(PaywallCopy.features, id: \.self) { feature in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(feature)
                        .font(.subheadline)
                }
            }
        }
        .padding()
    }

    private var productsSection: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if let pendingMessage {
                Text(pendingMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if offers.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()

                    Text("Loading Products...")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task {
                            await store.loadProducts()
                            syncFromStore()
                        }
                    } label: {
                        Label("Refresh Products", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 20)
            } else {
                ForEach(offers) { offer in
                    Button {
                        purchase(offer)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(offer.displayName)
                                    .font(.headline)
                                Text(offer.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(offer.displayPrice)
                                .font(.headline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPurchasing)
                }
            }
        }
    }

    private var restoreButton: some View {
        Button {
            Task {
                do {
                    try await store.restorePurchases()
                    syncFromStore()
                } catch {
                    syncFromStore()
                    errorMessage = error.localizedDescription
                }
            }
        } label: {
            Text("Restore Purchases")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func purchase(_ offer: PaywallProductOffer) {
        isPurchasing = true
        pendingMessage = nil
        Task {
            defer { isPurchasing = false }
            do {
                let outcome = try await store.purchase(offer)
                syncFromStore()
                if outcome == .pending {
                    pendingMessage = "Your purchase is pending approval. It will appear once the App Store completes it."
                }
            } catch {
                syncFromStore()
                errorMessage = error.localizedDescription
            }
        }
    }
}
#endif
