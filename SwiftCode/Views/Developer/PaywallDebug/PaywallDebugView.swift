import SwiftUI

struct PaywallDebugView: View {
    @StateObject private var entitlementManager = EntitlementManager.shared
    @State private var showPaywall = false

    var body: some View {
        Form {
            Section("Pro Status Control") {
                HStack {
                    Text("Current Status:")
                    Spacer()
                    Text(entitlementManager.isProUser ? "PRO" : "FREE")
                        .bold()
                        .foregroundStyle(entitlementManager.isProUser ? .green : .orange)
                }

                Button("Grant Pro Access") {
                    entitlementManager.updateProStatus(isPro: true)
                }
                .foregroundStyle(.green)

                Button("Revoke Pro Access") {
                    entitlementManager.updateProStatus(isPro: false)
                }
                .foregroundStyle(.red)
            }

            Section("Presentation") {
                Button("Force Show Paywall") {
                    showPaywall = true
                }
            }
        }
        .navigationTitle("Paywall Debug")
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}
