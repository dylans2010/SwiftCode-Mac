import SwiftUI

@MainActor
struct GitConflictBannerView: View {
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(count) Merge Conflicts Detected")
                            .font(.headline)
                            .foregroundColor(.red)
                        Text("Resolve these conflicts before committing your changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Resolve Manual") { }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
                .padding()
            }
            .groupBoxStyle(ModernGroupBoxStyle())
        }
        .sourceControlEmbedded()
    }
}
