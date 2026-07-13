import SwiftUI
import os.log

struct BundleAssetItem: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let color: Color
}

@Observable
@MainActor
final class BundleSizeAnalyzerViewModel {
    var totalSize: String = "24.6 MB"
    var assets: [BundleAssetItem] = [
        BundleAssetItem(name: "Compiled Binary (Swift Executable)", size: "12.4 MB", color: .blue),
        BundleAssetItem(name: "Assets Catalog (Media/Images)", size: "6.8 MB", color: .orange),
        BundleAssetItem(name: "Storyboard & Nibs Layouts", size: "3.1 MB", color: .purple),
        BundleAssetItem(name: "Metadata & Plist configurations", size: "1.2 MB", color: .pink),
        BundleAssetItem(name: "Localization Resources", size: "1.1 MB", color: .green)
    ]
}

struct BundleSizeAnalyzerDevToolView: View {
    @State private var viewModel = BundleSizeAnalyzerViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Analyze compiled application bundle footprints, identifying largest target asset sizes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Total Application Size")
                        .font(.headline)
                    Text(viewModel.totalSize)
                        .font(.system(.largeTitle, design: .rounded))
                        .bold()
                        .foregroundColor(.blue)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                Divider()

                Text("Asset Type Distribution")
                    .font(.headline)

                ForEach(viewModel.assets) { asset in
                    HStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(asset.color)
                            .frame(width: 12, height: 12)

                        Text(asset.name)
                            .font(.body)

                        Spacer()

                        Text(asset.size)
                            .font(.system(.body, design: .monospaced))
                            .bold()
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .navigationTitle("Bundle Size Analyzer")
    }
}
