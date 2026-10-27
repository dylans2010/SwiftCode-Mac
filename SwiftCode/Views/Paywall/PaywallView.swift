import SwiftUI
import StoreKit

struct PaywallView: View {
    @StateObject private var storeManager = StoreKitManager.shared
    @Environment(\.dismiss) private var dismiss

    let features = [
        "AI Documentation Insights",
        "Deployments (Netlify, Vercel, GitHub Pages)",
        "Advanced Debug Tools",
        "Extension Marketplace",
        "Binary Tool Integrations",
        "CI Builds"
    ]

    var body: some View {
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
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
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
            ForEach(features, id: \.self) { feature in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text(feature)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .liquidGlass(style: .standard, cornerRadius: 16)
    }

    private var productsSection: some View {
        VStack(spacing: 12) {
            if storeManager.products.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.orange)

                    Text("Loading Products...")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task {
                            await storeManager.loadProducts()
                        }
                    } label: {
                        Label("Refresh Products", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 20)
                .onAppear {
                    // Trigger load on appear in case it hasn't started
                    Task {
                        await storeManager.loadProducts()
                    }
                }
            } else {
                ForEach(storeManager.products) { product in
                    Button {
                        Task {
                            try? await storeManager.purchase(product)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(product.displayName)
                                    .font(.headline)
                                Text(product.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(product.displayPrice)
                                .font(.headline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        }
    }

    private var restoreButton: some View {
        Button {
            Task {
                try? await storeManager.restorePurchases()
            }
        } label: {
            Text("Restore Purchases")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

#Preview {
    PaywallView()
}
