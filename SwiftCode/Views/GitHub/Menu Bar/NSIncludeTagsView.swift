import SwiftUI

public struct NSIncludeTagsView: View {
    @State private var includeTags = true
    @State private var successMsg = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Include Tags", systemImage: "tag.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Toggle("Push tags alongside commits (--tags)", isOn: $includeTags)
                .toggleStyle(.checkbox)

            if !successMsg.isEmpty {
                Text(successMsg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Execute Tag Push") {
                successMsg = "Tags push completed with --tags option."
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(width: 280)
    }
}
