import SwiftUI

struct CodexUsageView: View {
    @ObservedObject private var tracker = CodexUsageTracker.shared
    @ObservedObject private var manager = CodexManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Usage", systemImage: "chart.bar.xaxis")
                .font(.headline)

            HStack {
                usageCard(title: "Estimated Tokens", value: "\(tracker.estimatedTotalTokens)")
                usageCard(title: "Requests", value: "\(tracker.requestCount)")
                usageCard(title: "Sessions", value: "\(tracker.sessionCount)")
            }

            Text(manager.usageMode == .unlimitedUserControlled ? "Tracked only, not limited" : "App managed limits are enforced for requests and tokens.")
                .font(.caption)
                .foregroundStyle(manager.usageMode == .unlimitedUserControlled ? .green : .secondary)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func usageCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
