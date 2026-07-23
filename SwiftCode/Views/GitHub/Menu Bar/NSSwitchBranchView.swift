import SwiftUI

public struct NSSwitchBranchView: View {
    @State private var selectedBranch = "main"
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Switch Branch", systemImage: "arrow.triangle.branch")
                .font(.headline)
                .foregroundStyle(.purple)

            Picker("Branch", selection: $selectedBranch) {
                Text("main").tag("main")
                Text("feature/ui").tag("feature/ui")
                Text("bugfix/concurrency").tag("bugfix/concurrency")
            }
            .pickerStyle(.menu)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Switch") {
                successMsg = "Successfully checked out '\(selectedBranch)'."
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}
