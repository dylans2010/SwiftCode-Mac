// Ported from SwiftCode-Legacy (Dylan's own code, MIT-authorised direct port).
// Rebuilt in Ycode style: default accent, no Legacy liquid-glass/orange styling.

import SwiftUI

struct DeploymentDebugView: View {
    @State private var logger = DeveloperLogStore.shared

    var body: some View {
        List {
            Section("Simulation") {
                Button("Simulate Deployment Success") {
                    DeveloperLogStore.shared.log("Deployment to Vercel succeeded", category: .deployments)
                }
                Button("Simulate Deployment Failure") {
                    DeveloperLogStore.shared.log("Deployment to Netlify failed: 401 Unauthorized", category: .deployments)
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
