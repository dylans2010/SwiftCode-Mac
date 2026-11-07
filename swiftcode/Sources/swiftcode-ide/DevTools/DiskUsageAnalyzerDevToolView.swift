import SwiftUI
import SwiftCodeUI
import os.log

struct DiskPathItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    var sizeBytes: Int64?
    var isPresent: Bool = true

    var sizeText: String {
        if let sizeBytes { return DevToolsDiskUsage.formatted(sizeBytes) }
        return isPresent ? "—" : "Not present"
    }
}

@Observable
@MainActor
final class DiskUsageAnalyzerViewModel {
    var paths: [DiskPathItem] = [
        DiskPathItem(name: "Xcode DerivedData", path: "~/Library/Developer/Xcode/DerivedData"),
        DiskPathItem(name: "SwiftPM Cache", path: "~/.swiftpm/cache"),
        DiskPathItem(name: "CocoaPods Cache", path: "~/Library/Caches/CocoaPods"),
        DiskPathItem(name: "Application Sandbox Support", path: "~/Library/Application Support/SwiftCode")
    ]
    var isScanning = false
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "DiskUsageAnalyzer")

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        let snapshot = paths
        Task.detached(priority: .userInitiated) {
            var updated = snapshot
            for index in updated.indices {
                let expanded = (updated[index].path as NSString).expandingTildeInPath
                let url = URL(fileURLWithPath: expanded)
                let exists = FileManager.default.fileExists(atPath: url.path)
                updated[index].isPresent = exists
                updated[index].sizeBytes = exists ? DevToolsDiskUsage.allocatedSize(of: url) : nil
            }
            await MainActor.run {
                self.paths = updated
                self.isScanning = false
            }
        }
    }

    func cleanPath(_ itemID: UUID) {
        guard let index = paths.firstIndex(where: { $0.id == itemID }) else { return }
        let item = paths[index]
        let expanded = (item.path as NSString).expandingTildeInPath
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: expanded))
            logger.info("Removed directory \(item.name) at \(item.path)")
            scan()
        } catch {
            errorMessage = "Could not clean \(item.name): \(error.localizedDescription)"
            logger.error("Failed to remove \(item.path): \(error.localizedDescription)")
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

                HStack(spacing: 12) {
                    Button {
                        viewModel.scan()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isScanning)

                    if viewModel.isScanning {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
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

                    Text(item.sizeText)
                        .font(.system(.body, design: .monospaced))
                        .bold()
                        .padding(.horizontal)

                    Button("Clean") {
                        viewModel.cleanPath(item.id)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(item.sizeBytes == nil)
                }
                .padding(.vertical, 4)
                .liquidGlass(style: .subtle, cornerRadius: 12)
            }
        }
        .navigationTitle("Disk Usage Analyzer")
        .onAppear {
            viewModel.scan()
        }
    }
}
