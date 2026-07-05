import SwiftUI

struct BuildDiagnosticsView: View {
    let logs = [
        BuildLogEntry(step: "Resolving Swift Packages", status: .success, duration: "1.2s"),
        BuildLogEntry(step: "Compiling Module SwiftCodeCore", status: .success, duration: "4.5s"),
        BuildLogEntry(step: "Compiling Main Target", status: .warning, duration: "12.1s", detail: "Unused variable 'temp' in SwiftCodeApp.swift:24"),
        BuildLogEntry(step: "Linking SwiftCode.app", status: .success, duration: "2.1s")
    ]

    var body: some View {
        List(logs) { entry in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: iconForStatus(entry.status))
                        .foregroundStyle(colorForStatus(entry.status))
                    Text(entry.step).font(.headline)
                    Spacer()
                    Text(entry.duration).font(.caption).foregroundStyle(.secondary)
                }

                if let detail = entry.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(8)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .listRowBackground(Color.white.opacity(0.05))
        }
        .navigationTitle("Build Diagnostics")
    }

    private func iconForStatus(_ status: BuildStatus) -> String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    private func colorForStatus(_ status: BuildStatus) -> Color {
        switch status {
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        }
    }
}

enum BuildStatus { case success, warning, failure }
struct BuildLogEntry: Identifiable {
    let id = UUID()
    let step: String
    let status: BuildStatus
    let duration: String
    var detail: String? = nil
}
