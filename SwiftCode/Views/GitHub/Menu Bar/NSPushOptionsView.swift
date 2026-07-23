import SwiftUI

public struct NSPushOptionsView: View {
    @State private var setTrackstream = true
    @State private var pushAllBranches = false
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Git Push Options", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.purple)

            Toggle("Set upstream tracking (--set-upstream)", isOn: $setTrackstream)
                .toggleStyle(.checkbox)

            Toggle("Push all branches (--all)", isOn: $pushAllBranches)
                .toggleStyle(.checkbox)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Apply & Push") {
                successMsg = "Pushed with custom configurations applied."
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}
