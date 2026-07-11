import SwiftUI

/// Monospaced build status, compiler diagnostic traces, and logs of the SwiftUI Preview Engine.
public struct PreviewConsoleView: View {
    @Environment(PreviewManager.self) private var previewManager

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Preview Build Console", systemImage: "text.alignleft")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if previewManager.isCompiling {
                    ProgressView().scaleEffect(0.6)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Console Stream Content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if previewManager.logStream.isEmpty {
                            Text("Waiting for compiler trigger...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(0..<previewManager.logStream.count, id: \.self) { index in
                                let log = previewManager.logStream[index]
                                Text(log)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(log.contains("succeeded") ? .green : (log.contains("failed") ? .red : .primary))
                                    .textSelection(.enabled)
                                    .tag(index)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(red: 0.08, green: 0.08, blue: 0.10))
                .onChange(of: previewManager.logStream.count) { _, newCount in
                    if newCount > 0 {
                        withAnimation {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}
