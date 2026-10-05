import SwiftUI

public struct CreateNewAppProgressView: View {
    public let config: CreateAppConfiguration
    public let log: String
    @Binding public var isCompleted: Bool
    @Binding public var createdAppPath: String?
    @Binding public var builtAppPath: String?

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.2)

            VStack(spacing: 8) {
                Text("Generating \(config.appName)...")
                    .font(.title2.bold())
                Text("Assist is autonomously scaffolding, implementing, building, and verifying your application.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "terminal")
                    Text("Execution Activity")
                        .font(.caption.bold())
                    Spacer()
                }

                ScrollView {
                    Text(log.isEmpty ? "Initializing create_new_app tool pipeline..." : log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .frame(height: 200)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}
