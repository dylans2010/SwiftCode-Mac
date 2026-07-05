import SwiftUI
import MultipeerConnectivity

struct TransferProjectsHomeView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @StateObject private var transferManager = ProjectTransferManager.shared
    @StateObject private var peerManager = PeerSessionManager.shared
    @State private var selectedPeer: MCPeerID?
    @State private var permission = TransferPermission.makePreset(.limitedEdit)
    @State private var showDevicePicker = false
    @State private var showIncomingAlert = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 20) {
                    Button {
                        showDevicePicker = true
                    } label: {
                        VStack {
                            Image(systemName: "paperplane.fill")
                                .font(.title)
                            Text("Send")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }

                    Button {
                        showIncomingAlert = true
                    } label: {
                        VStack {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.title)
                            Text("Receive")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            if let project = projectManager.activeProject {
                Section("Active Project: \(project.name)") {
                    NavigationLink {
                        PermissionConfigView(permission: $permission)
                            .navigationTitle("Permissions")
                    } label: {
                        Label("Configure Permissions", systemImage: "lock.shield")
                    }

                    NavigationLink("Choose Device") {
                        DevicePickerView(selectedPeer: $selectedPeer)
                    }

                    if let selectedPeer {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Target Device")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(selectedPeer.displayName)
                                    .font(.headline)
                            }
                            Spacer()
                            if peerManager.peerStates[selectedPeer.displayName] == .connected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        Button {
                            Task { try? await transferManager.startTransfer(project: project, to: selectedPeer, permission: permission) }
                        } label: {
                            Text("Initiate Transfer")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(peerManager.peerStates[selectedPeer.displayName] != .connected)
                    }
                }
            }

            Section("Connection Status") {
                if peerManager.nearbyPeers.isEmpty {
                    Text("Scanning for nearby devices...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(peerManager.nearbyPeers, id: \.self) { peer in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(peer.displayName)
                                Text(statusString(for: peer))
                                    .font(.caption)
                                    .foregroundStyle(statusColor(for: peer))
                            }
                            Spacer()
                            if peerManager.peerStates[peer.displayName] != .connected {
                                Button("Connect") {
                                    peerManager.invite(peer)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            Section("Incoming") {
                if transferManager.incomingSession != nil {
                    IncomingTransferView()
                } else {
                    Text("No incoming transfers")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Progress") {
                TransferProgressView()
            }
        }
        .navigationTitle("Transfer Projects")
        .sheet(isPresented: $showDevicePicker) {
            NavigationStack {
                DevicePickerView(selectedPeer: $selectedPeer)
                    .navigationTitle("Select Device")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showDevicePicker = false }
                        }
                    }
            }
        }
        .alert("Receive Mode Active", isPresented: $showIncomingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your device is now discoverable. Incoming project transfer requests will appear in the 'Incoming' section below.")
        }
    }

    private func statusString(for peer: MCPeerID) -> String {
        switch peerManager.peerStates[peer.displayName] {
        case .notConnected: return "Not Connected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .none: return "Available"
        @unknown default: return "Unknown"
        }
    }

    private func statusColor(for peer: MCPeerID) -> Color {
        switch peerManager.peerStates[peer.displayName] {
        case .connected: return .green
        case .connecting: return .orange
        default: return .secondary
        }
    }
}
