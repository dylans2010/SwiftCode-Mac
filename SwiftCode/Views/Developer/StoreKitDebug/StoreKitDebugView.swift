import SwiftUI

struct StoreKitDebugView: View {
    @StateObject private var entitlementManager = EntitlementManager.shared

    var body: some View {
        Form {
            Section("Current Status") {
                HStack {
                    Text("Pro Status")
                    Spacer()
                    Text(entitlementManager.isProUser ? "Active" : "Inactive")
                        .foregroundColor(entitlementManager.isProUser ? .green : .red)
                }
            }

            Section("Simulations") {
                Button("Simulate Purchase Success") {
                    entitlementManager.updateProStatus(isPro: true)
                }

                Button("Simulate Purchase Failure") {
                    entitlementManager.updateProStatus(isPro: false)
                }

                Button("Simulate Subscription Expired") {
                    entitlementManager.updateProStatus(isPro: false)
                }

                Button("Force Restore Entitlements") {
                    entitlementManager.updateProStatus(isPro: true)
                }
            }
        }
        .navigationTitle("StoreKit Debug")
    }
}
