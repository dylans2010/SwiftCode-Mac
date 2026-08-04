import SwiftUI

struct PreferencesView: View {
    @State private var scanOnLaunch = true
    @State private var alertOnPackageUpdate = true
    @State private var enableTelemetry = true
    @State private var maxArchiveCount = 10

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Operations Preferences")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Configure automated scans, notifications thresholds, and storage quotas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Automated Actions")
                            .font(.headline)

                        Toggle("Run full diagnostics integrity scan at window launch", isOn: $scanOnLaunch)
                        Toggle("Alert immediately when dependency package update is discovered", isOn: $alertOnPackageUpdate)
                        Toggle("Send anonymous crash/performance telemetry", isOn: $enableTelemetry)
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Archive Thresholds")
                            .font(.headline)

                        Stepper("Maximum retained archives in local registry: \(maxArchiveCount)", value: $maxArchiveCount, in: 5...30)
                        Text("When limit is reached, older archives are automatically compressed to zip and moved to backups directory.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
    }
}
