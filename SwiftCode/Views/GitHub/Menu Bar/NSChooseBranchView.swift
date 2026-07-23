import SwiftUI

public struct NSChooseBranchView: View {
    @State private var selectedBranch = "main"
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Choose Branch", systemImage: "arrow.triangle.branch")
                .font(.headline)
                .foregroundStyle(.cyan)

            Picker("Branch", selection: $selectedBranch) {
                Text("main").tag("main")
                Text("development").tag("development")
                Text("release-v1.0").tag("release-v1.0")
            }
            .pickerStyle(.menu)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Switch & Checkout") {
                successMsg = "Switched branch to '\(selectedBranch)'."
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}
