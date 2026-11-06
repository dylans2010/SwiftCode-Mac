// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/DependencyHealthView.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: MISSING at bc28f653. Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI
import SwiftCodeUI

struct DependencyHealthView: View {
    @State private var isScanning = false
    @State private var issues: [DependencyIssue] = []

    var body: some View {
        VStack {
            if isScanning {
                ProgressView("Analyzing Dependencies...")
                    .padding()
            } else if issues.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("All Dependencies Healthy")
                        .font(.headline)
                    Button("Scan Again") { runScan() }
                        .buttonStyle(.bordered)
                }
            } else {
                List(issues) { issue in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.name).font(.subheadline.bold())
                            Text(issue.description).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("Dependency Health")
        .onAppear { runScan() }
    }

    private func runScan() {
        isScanning = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            issues = [
                DependencyIssue(name: "ZIPFoundation", description: "Version mismatch in build target"),
                DependencyIssue(name: "Highlightr", description: "Duplicate symbols detected in project index")
            ]
            isScanning = false
        }
    }
}

struct DependencyIssue: Identifiable {
    let id = UUID()
    let name: String
    let description: String
}
