import SwiftUI
import os.log

struct DiskPathItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    var size: String
}

@Observable
@MainActor
final class DiskUsageAnalyzerViewModel {
    var paths: [DiskPathItem] = [
        DiskPathItem(name: "Xcode DerivedData", path: "~/Library/Developer/Xcode/DerivedData", size: "4.8 GB"),
        DiskPathItem(name: "SwiftPM Cache", path: "~/.swiftpm/cache", size: "1.2 GB"),
        DiskPathItem(name: "CocoaPods Cache", path: "~/Library/Caches/CocoaPods", size: "840 MB"),
        DiskPathItem(name: "Application Sandbox Support", path: "~/Library/Application Support/SwiftCode", size: "120 MB")
    ]

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "DiskUsageAnalyzer")

    func cleanPath(_ itemID: UUID) {
        if let index = paths.firstIndex(where: { $0.id == itemID }) {
            let name = paths[index].name
            paths[index].size = "0 KB"
            logger.info("Purged directory path size to mock cleanup for: \(name)")
        }
    }
}

struct DiskUsageAnalyzerDevToolView: View {
    @State private var viewModel = DiskUsageAnalyzerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Scan and clean standard developer directories and caches on macOS disk storage.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List(viewModel.paths) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.headline)
                        Text(item.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(item.size)
                        .font(.system(.body, design: .monospaced))
                        .bold()
                        .padding(.horizontal)

                    Button("Clean") {
                        viewModel.cleanPath(item.id)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(item.size == "0 KB")
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Disk Usage Analyzer")
    }
}
