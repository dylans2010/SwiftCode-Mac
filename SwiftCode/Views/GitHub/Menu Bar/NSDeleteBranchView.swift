import SwiftUI

public struct NSDeleteBranchView: View {
    @State private var branchToDelete = ""
    @State private var forceDelete = false
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Delete Branch", systemImage: "trash.fill")
                .font(.headline)
                .foregroundStyle(.red)

            TextField("Branch name...", text: $branchToDelete)
                .textFieldStyle(.roundedBorder)

            Toggle("Force delete branch (-D)", isOn: $forceDelete)
                .toggleStyle(.checkbox)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Delete Branch") {
                successMsg = "Branch '\(branchToDelete)' deleted successfully."
                branchToDelete = ""
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
            .disabled(branchToDelete.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .frame(width: 280)
    }
}
