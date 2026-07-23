import SwiftUI

public struct NSCreateBranchView: View {
    @State private var branchName = ""
    @State private var checkout = true
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Create Branch", systemImage: "plus.circle.fill")
                .font(.headline)
                .foregroundStyle(.cyan)

            TextField("Branch name...", text: $branchName)
                .textFieldStyle(.roundedBorder)

            Toggle("Checkout branch immediately", isOn: $checkout)
                .toggleStyle(.checkbox)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Create Branch") {
                successMsg = "Branch '\(branchName)' created successfully."
                branchName = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .frame(width: 280)
    }
}
