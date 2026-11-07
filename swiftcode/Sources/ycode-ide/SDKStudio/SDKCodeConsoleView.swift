import AppKit
import SwiftUI

private struct SDKCodeConsoleRow: View {
    let entry: SDKConsoleEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            SDKCodeConsoleStreamBadge(stream: entry.stream)
            Text(entry.text)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }
}

private struct SDKCodeConsoleStreamBadge: View {
    let stream: SDKConsoleStream

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontDesign(.monospaced)
            .bold()
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Stream: \(stream.rawValue)")
    }

    private var label: String {
        switch stream {
        case .stdout: return "OUT"
        case .stderr: return "ERR"
        case .system: return "SYS"
        }
    }

    private var color: Color {
        switch stream {
        case .stdout: return .secondary
        case .stderr: return .red
        case .system: return .blue
        }
    }
}
