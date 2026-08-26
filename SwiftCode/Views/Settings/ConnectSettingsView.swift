import SwiftUI

struct ConnectSettingsView: View {
    @State private var trustStore = TrustStore.shared
    @State private var connectServer = ConnectServer.shared
    @State private var bonjour = BonjourAdvertiser.shared

    @State private var selectedDeviceID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status Header
            HStack(spacing: 12) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 28))
                    .foregroundColor(connectServer.isRunning ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SwiftCode Connect Host")
                        .font(.headline)
                    Text(connectServer.isRunning ? "Advertising on local network as '\(bonjour.macName)' (Port \(bonjour.advertisedPort ?? 8088))" : "Service Stopped")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle(connectServer.isRunning ? "Active" : "Disabled", isOn: Binding(
                    get: { connectServer.isRunning },
                    set: { newValue in
                        if newValue {
                            connectServer.startServer()
                        } else {
                            connectServer.stopServer()
                        }
                    }
                ))
                .toggleStyle(.switch)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Divider()

            // Active Connections Section
            Text("Active Connections (\(connectServer.activeSessions.count))")
                .font(.headline)

            if connectServer.activeSessions.isEmpty {
                Text("No iOS devices currently connected.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                List(connectServer.activeSessions) { session in
                    HStack {
                        Image(systemName: "iphone")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text(session.deviceName ?? "iOS Device")
                                .font(.body).bold()
                            Text("Session ID: \(session.id.uuidString.prefix(8))... • Status: \(session.state.rawValue)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Disconnect") {
                            session.disconnect()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 100)
                .cornerRadius(6)
            }

            Divider()

            // Paired & Trusted Devices Section
            Text("Trusted iOS Devices (\(trustStore.trustedDevices.count))")
                .font(.headline)

            if trustStore.trustedDevices.isEmpty {
                Text("No paired devices registered.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                List(trustStore.trustedDevices) { device in
                    HStack {
                        Image(systemName: device.isRevoked ? "iphone.slash" : "iphone")
                            .foregroundColor(device.isRevoked ? .red : .green)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(device.name)
                                    .font(.body).bold()
                                if device.isRevoked {
                                    Text("Revoked")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.2))
                                        .foregroundColor(.red)
                                        .cornerRadius(4)
                                }
                            }
                            Text("Model: \(device.model) • Paired: \(device.pairingDate.formatted(date: .numeric, time: .omitted))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if device.isRevoked {
                            Button("Trust") {
                                trustStore.registerDevice(TrustedDevice(
                                    id: device.id,
                                    name: device.name,
                                    model: device.model,
                                    pairingDate: device.pairingDate,
                                    lastConnection: Date(),
                                    sessionToken: device.sessionToken,
                                    permissions: device.permissions,
                                    isRevoked: false
                                ))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Button("Revoke Access") {
                                trustStore.revokeDevice(deviceID: device.id)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.small)
                        }

                        Button(role: .destructive) {
                            trustStore.deleteDevice(deviceID: device.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 180)
                .cornerRadius(6)
            }
        }
        .padding()
        .sheet(item: Binding(
            get: { PairingManager.shared.activePairingRequest },
            set: { _ in }
        )) { _ in
            ConnectPairingApprovalSheet()
        }
        .onAppear {
            if !connectServer.isRunning {
                connectServer.startServer()
            }
        }
    }
}
