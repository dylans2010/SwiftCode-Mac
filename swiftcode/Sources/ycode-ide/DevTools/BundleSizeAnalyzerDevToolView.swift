import SwiftUI
import YcodeUI
import os.log
#if canImport(AppKit)
import AppKit
#endif

struct AppBundleSizeBreakdown: Sendable {
    let bundleName: String
    let totalBytes: Int64
    let categories: [(label: String, bytes: Int64)]

    static func measure(bundle: URL) -> AppBundleSizeBreakdown {
        let fileManager = FileManager.default
        let total = DevToolsDiskUsage.allocatedSize(of: bundle) ?? 0

        func allocatedSize(of url: URL) -> Int64 {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
            if !isDir.boolValue {
                return (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize.map(Int64.init) ?? 0
            }
            return DevToolsDiskUsage.allocatedSize(of: url) ?? 0
        }

        func sumFiles(where predicate: (URL) -> Bool) -> Int64 {
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
            guard let enumerator = fileManager.enumerator(
                at: bundle,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { return 0 }
            var sum: Int64 = 0
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                      values.isDirectory != true,
                      predicate(fileURL) else { continue }
                sum += Int64(values.totalFileAllocatedSize ?? 0)
            }
            return sum
        }

        var executableBytes: Int64 = 0
        if let bundleObject = Bundle(url: bundle), let executableURL = bundleObject.executableURL {
            executableBytes = allocatedSize(of: executableURL)
        }
        let assetsBytes = sumFiles { $0.pathExtension.lowercased() == "car" }
        let nibBytes = sumFiles {
            $0.pathExtension.lowercased() == "nib" || $0.path.contains(".storyboardc")
        }
        let plistBytes = sumFiles { $0.pathExtension.lowercased() == "plist" }
        let localizationBytes = sumFiles { $0.path.contains(".lproj") }
        let categorized = executableBytes + assetsBytes + nibBytes + plistBytes + localizationBytes
        let otherBytes = max(0, total - categorized)
        return AppBundleSizeBreakdown(
            bundleName: bundle.lastPathComponent,
            totalBytes: total,
            categories: [
                (label: "Executable", bytes: executableBytes),
                (label: "Assets Catalog (.car)", bytes: assetsBytes),
                (label: "Storyboards & Nibs", bytes: nibBytes),
                (label: "Metadata & Plists", bytes: plistBytes),
                (label: "Localization Resources", bytes: localizationBytes),
                (label: "Other", bytes: otherBytes),
            ])
    }
}

@Observable
@MainActor
final class BundleSizeAnalyzerViewModel {
    var selectedBundleURL: URL?
    var breakdown: AppBundleSizeBreakdown?
    var isMeasuring = false
    var statusMessage: String?

    private static let categoryColors: [Color] = [.blue, .orange, .purple, .pink, .green, .teal]

    func color(forCategoryAt index: Int) -> Color {
        Self.categoryColors[index % Self.categoryColors.count]
    }
}

struct BundleSizeAnalyzerDevToolView: View {
    @State private var viewModel = BundleSizeAnalyzerViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Analyze compiled application bundle footprints, identifying largest target asset sizes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let bundleURL = viewModel.selectedBundleURL {
                    Text(bundleURL.lastPathComponent)
                        .font(.subheadline.bold())
                    Text(bundleURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("No bundle selected. Pick an .app bundle to measure it on disk.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Total Application Size")
                        .font(.headline)
                    if viewModel.isMeasuring {
                        ProgressView("Measuring bundle…")
                    } else if let breakdown = viewModel.breakdown {
                        Text(DevToolsDiskUsage.formatted(breakdown.totalBytes))
                            .font(.system(.largeTitle, design: .rounded))
                            .bold()
                            .foregroundColor(.blue)
                    } else {
                        Text("—")
                            .font(.system(.largeTitle, design: .rounded))
                            .bold()
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(style: .standard, cornerRadius: 10)

                Divider()

                Text("Asset Type Distribution")
                    .font(.headline)

                if let breakdown = viewModel.breakdown {
                    ForEach(breakdown.categories.indices, id: \.self) { index in
                        let category = breakdown.categories[index]
                        HStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(viewModel.color(forCategoryAt: index))
                                .frame(width: 12, height: 12)

                            Text(category.label)
                                .font(.body)

                            Spacer()

                            Text(DevToolsDiskUsage.formatted(category.bytes))
                                .font(.system(.body, design: .monospaced))
                                .bold()
                        }
                        .padding(.vertical, 4)
                    }
                } else if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

#if canImport(AppKit)
                Button(viewModel.selectedBundleURL == nil ? "Select .app Bundle…" : "Select a Different Bundle…") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowedFileTypes = ["app"]
                    if panel.runModal() == .OK, let url = panel.url {
                        viewModel.selectedBundleURL = url
                        viewModel.statusMessage = nil
                        Task { await measure(url) }
                    }
                }
                .buttonStyle(.borderedProminent)
#else
                Text("Bundle picking requires macOS (AppKit).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
#endif
            }
            .padding()
        }
        .navigationTitle("Bundle Size Analyzer")
    }

    private func measure(_ bundle: URL) async {
        viewModel.isMeasuring = true
        defer { viewModel.isMeasuring = false }
        let breakdown = await Task.detached(priority: .userInitiated) {
            AppBundleSizeBreakdown.measure(bundle: bundle)
        }.value
        viewModel.breakdown = breakdown
        if breakdown.totalBytes == 0 {
            viewModel.statusMessage = "The selected bundle measured 0 bytes — it may be empty or unreadable."
        }
    }
}
