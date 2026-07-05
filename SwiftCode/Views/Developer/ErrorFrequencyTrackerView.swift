import SwiftUI

struct ErrorFrequencyTrackerView: View {
    let errors = [
        ErrorStat(message: "Network Timeout", count: 42, color: .red),
        ErrorStat(message: "Invalid API Key", count: 12, color: .orange),
        ErrorStat(message: "File Not Found", count: 8, color: .yellow),
        ErrorStat(message: "JSON Decoding Failed", count: 5, color: .blue)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(errors) { error in
                    HStack(spacing: 16) {
                        Circle()
                            .fill(error.color)
                            .frame(width: 40, height: 40)
                            .overlay(Text("\(error.count)").font(.caption.bold()).foregroundStyle(.white))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(error.message).font(.headline)
                            ProgressView(value: Double(error.count), total: 50)
                                .tint(error.color)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle("Error Tracker")
    }
}

struct ErrorStat: Identifiable {
    let id = UUID()
    let message: String
    let count: Int
    let color: Color
}
