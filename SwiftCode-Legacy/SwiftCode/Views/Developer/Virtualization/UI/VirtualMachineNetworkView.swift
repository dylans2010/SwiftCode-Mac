import SwiftUI

public struct VirtualMachineNetworkView: View {
    public let vmID: UUID?

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var ruleName: String = ""
    @State private var hostPort: String = ""
    @State private var guestPort: String = ""
    @State private var selectedProto: String = "TCP"

    public init(vmID: UUID?) {
        self.vmID = vmID
    }

    private var activeVM: VirtualMachine? {
        guard let id = vmID else { return stateStore.virtualMachines.first }
        return stateStore.virtualMachines.first { $0.id == id }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NAT Ports & Local Port Forwarding")
                    .font(.headline)
                Text("Map network ports between your Mac and the guest sandbox so web servers and local clients can communicate securely.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let vm = activeVM {
                GroupBox(label: Text("Add Network Forwarding Rule").font(.headline)) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rule Label")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                TextField("e.g. Vapor server", text: $ruleName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Host Port (Mac)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                TextField("8080", text: $hostPort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 110)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Guest Port (VM)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                TextField("8080", text: $guestPort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 110)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Protocol")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Picker("", selection: $selectedProto) {
                                    Text("TCP").tag("TCP")
                                    Text("UDP").tag("UDP")
                                }
                                .frame(width: 75)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(" ") // Align with text fields
                                    .font(.caption)
                                Button("Add Rule") {
                                    addRule(vm.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(ruleName.isEmpty || hostPort.isEmpty || guestPort.isEmpty)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox(label: Text("Active Port Mappings").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        if vm.portForwardings.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "network.badge.shield.half.filled")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)

                                Text("No Port Forwarding Rules Configured")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Text("Forward ports above so you can access databases, web APIs, or SSH services running inside Linux directly from Safari or other Mac clients.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 420)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(vm.portForwardings) { rule in
                                    HStack {
                                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                                            .foregroundStyle(.blue)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(rule.name)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                            Text("\(rule.protocolType) • Localhost:\(rule.hostPort) ➔ Guest Workspace:\(rule.guestPort)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Button(role: .destructive) {
                                            removeRule(vm.id, ruleID: rule.id)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                    }
                                    .padding(.vertical, 8)

                                    if rule.id != vm.portForwardings.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Networking Inline Help Info
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Understanding NAT Mode Port Mappings")
                            .font(.caption)
                            .fontWeight(.bold)
                        Text("NAT (Network Address Translation) isolates your guest operating system from local external LAN snooping. To connect from Safari or other local clients, mapping host ports to guest ports acts as a secure local tunnel.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(8)

            } else {
                ContentUnavailableView(
                    "No Environment Selected",
                    systemImage: "network",
                    description: Text("Select an active environment from the sidebar to configure port maps.")
                )
            }
        }
    }

    private func addRule(_ vmID: UUID) {
        let name = ruleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let hPort = Int(hostPort),
              let gPort = Int(guestPort) else { return }

        try? VMNetworkManager.shared.addPortForwarding(
            vmID: vmID,
            name: name,
            hostPort: hPort,
            guestPort: gPort,
            protocolType: selectedProto
        )
        ruleName = ""
        hostPort = ""
        guestPort = ""
        stateStore.refreshVM(vmID)
        stateStore.addLog("Configured network tunnel mapping '\(name)' (Port \(hPort) ➔ \(gPort)).", type: .success)
    }

    private func removeRule(_ vmID: UUID, ruleID: UUID) {
        try? VMNetworkManager.shared.removePortForwarding(vmID: vmID, ruleID: ruleID)
        stateStore.refreshVM(vmID)
        stateStore.addLog("Removed network port mapping rule from NAT stack.", type: .warning)
    }
}
