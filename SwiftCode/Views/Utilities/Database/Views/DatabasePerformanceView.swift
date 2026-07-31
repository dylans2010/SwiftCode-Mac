import SwiftUI

struct DatabasePerformanceView: View {
    @State private var slowQueries: [String] = [
        "SELECT * FROM orders WHERE total_amount > 100; (Cost: High)",
        "SELECT * FROM products WHERE sku = 'PROD-101'; (Cost: Moderate)"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Performance & Recommendations")
                    .font(.title2.bold())

                GroupBox("AI Optimization Scoring") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Database Health Score:")
                            Spacer()
                            Text("92/100")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        ProgressView(value: 0.92)
                            .tint(.green)
                    }
                    .padding(8)
                }

                GroupBox("Slow Queries & Index Recommendations") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(slowQueries, id: \.self) { q in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(q)
                                    .font(.caption)
                                Spacer()
                                Button("Add Index") {
                                    // Add fast performance index
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .padding()
        }
    }
}
