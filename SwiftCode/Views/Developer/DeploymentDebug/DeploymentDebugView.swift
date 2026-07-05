import SwiftUI

struct DeploymentDebugView: View {
    @StateObject private var logger = InternalLoggingManager.shared

    var body: some View {
        List {
            Section("Simulation") {
                Button("Simulate Deployment Success") {
                    InternalLoggingManager.shared.log("Deployment to Vercel succeeded", category: .deployments)
                }
                Button("Simulate Deployment Failure") {
                    InternalLoggingManager.shared.log("Deployment to Netlify failed: 401 Unauthorized", category: .deployments)
                }
            }

            Section("Deployment History") {
                let logs = logger.logs.filter { $0.category == .deployments }
                if logs.isEmpty {
                    Text("No deployment logs").foregroundColor(.secondary)
                } else {
                    ForEach(logs) { log in
                        VStack(alignment: .leading) {
                            Text(log.message)
                                .font(.caption)
                            Text(log.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Deployment Debug")
    }
}
