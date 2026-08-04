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
        VStack(alignment: .leading, spacing: 16) {
            Text("NAT Networking & Port Forwarding")
                .font(.headline)
            Text("Bridge connections between your macOS host and the guest container kernel. Port forwarding maps network ports so local macOS servers can connect directly to guest processes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let vm = activeVM {
                GroupBox(label: Text("Add Network Forwarding Rule").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("Rule Name (e.g. Node API)", text: $ruleName)
                                .textFieldStyle(.roundedBorder)

                            TextField("Host Port (e.g. 3000)", text: $hostPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)

                            TextField("Guest Port (e.g. 3000)", text: $guestPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)

                            Picker("", selection: $selectedProto) {
                                Text("TCP").tag("TCP")
                                Text("UDP").tag("UDP")
                            }
                            .frame(width: 80)

                            Button("Add Rule") {
                                addRule(vm.id)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox(label: Text("Active Port Mappings").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        if vm.portForwardings.isEmpty {
                            Text("No active port forwarding mappings. Map ports above to access guest servers from Safari or API clients.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(vm.portForwardings) { rule in
                                HStack {
                                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                                        .foregroundStyle(.blue)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rule.name)
                                            .fontWeight(.bold)
                                        Text("\(rule.protocolType) • Localhost:\(rule.hostPort) ➔ Guest VM:\(rule.guestPort)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button(role: .destructive) {
                                        removeRule(vm.id, ruleID: rule.id)
                                    } label: {
                                        Text("Remove Mapping")
                                            .foregroundStyle(.red)
                                    }
                                    .controlSize(.small)
                                }
                                .padding(.vertical, 4)
                                if rule.id != vm.portForwardings.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            } else {
                ContentUnavailableView(
                    "No Virtual Machine",
                    systemImage: "network",
                    description: Text("Select a VM from the sidebar to inspect networks.")
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
        stateStore.addLog("Configured port mapping '\(name)' (Host:\(hPort) ➔ Guest:\(gPort)).", type: .success)
    }

    private func removeRule(_ vmID: UUID, ruleID: UUID) {
        try? VMNetworkManager.shared.removePortForwarding(vmID: vmID, ruleID: ruleID)
        stateStore.refreshVM(vmID)
        stateStore.addLog("Removed network port mapping rule.", type: .warning)
    }
}
