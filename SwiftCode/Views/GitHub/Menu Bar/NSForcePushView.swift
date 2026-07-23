import SwiftUI

public struct NSForcePushView: View {
    @State private var useForceWithLease = true
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Force Push", systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text("WARNING: Force pushing overwrites history on the remote origin.")
                .font(.caption2)
                .foregroundStyle(.red)

            Toggle("Use force with lease (Safer)", isOn: $useForceWithLease)
                .toggleStyle(.checkbox)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Force Push") {
                successMsg = "Force push triggered successfully."
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}
