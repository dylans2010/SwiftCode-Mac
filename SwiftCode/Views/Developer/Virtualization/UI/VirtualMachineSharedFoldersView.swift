import SwiftUI

public struct VirtualMachineSharedFoldersView: View {
    public let vmID: UUID?

    @State private var stateStore = VirtualizationStateStore.shared
    @State private var folderName: String = ""
    @State private var hostPath: String = ""
    @State private var guestMountPoint: String = "/mnt/workspace"
    @State private var isReadOnly: Bool = false

    public init(vmID: UUID?) {
        self.vmID = vmID
    }

    private var activeVM: VirtualMachine? {
        guard let id = vmID else { return stateStore.virtualMachines.first }
        return stateStore.virtualMachines.first { $0.id == id }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shared Folders & Mounting Directories")
                .font(.headline)
            Text("Mount local directories from your host macOS into the virtual machine's internal files structure.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let vm = activeVM {
                GroupBox(label: Text("Configure Mounting Folder").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("Folder Mount Name", text: $folderName)
                                .textFieldStyle(.roundedBorder)

                            TextField("Guest Mount Directory Path", text: $guestMountPoint)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 12) {
                            TextField("Host System Path", text: $hostPath)
                                .textFieldStyle(.roundedBorder)

                            Button("Choose folder...") {
                                let openPanel = NSOpenPanel()
                                openPanel.canChooseDirectories = true
                                openPanel.canChooseFiles = false
                                openPanel.allowsMultipleSelection = false
                                if openPanel.runModal() == .OK, let url = openPanel.url {
                                    hostPath = url.path
                                    if folderName.isEmpty {
                                        folderName = url.lastPathComponent
                                    }
                                }
                            }
                        }

                        HStack {
                            Toggle("Mount Read-Only", isOn: $isReadOnly)
                                .toggleStyle(.checkbox)
                            Spacer()
                            Button("Mount Directory") {
                                mountFolder(vm.id)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox(label: Text("Mounted Directories").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        if vm.sharedFolders.isEmpty {
                            Text("No folders currently shared. Configure a local directory above to map project directories.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(vm.sharedFolders) { folder in
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.orange)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.name)
                                            .fontWeight(.bold)
                                        Text("Host path: \(folder.hostPath) ➔ Guest path: \(folder.guestMountPoint) \(folder.isReadOnly ? "(Read-Only)" : "(Read-Write)")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button(role: .destructive) {
                                        unmountFolder(vm.id, folderID: folder.id)
                                    } label: {
                                        Text("Unmount")
                                            .foregroundStyle(.red)
                                    }
                                    .controlSize(.small)
                                }
                                .padding(.vertical, 4)
                                if folder.id != vm.sharedFolders.last?.id {
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
                    systemImage: "folder.badge.plus",
                    description: Text("Select a virtual machine to configure file mounts.")
                )
            }
        }
    }

    private func mountFolder(_ vmID: UUID) {
        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = hostPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let guest = guestMountPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !host.isEmpty, !guest.isEmpty else { return }

        try? VMSharedFolderManager.shared.addSharedFolder(
            vmID: vmID,
            name: name,
            hostPath: host,
            guestMountPoint: guest,
            isReadOnly: isReadOnly
        )
        folderName = ""
        hostPath = ""
        stateStore.refreshVM(vmID)
        stateStore.addLog("Mounted directory '\(name)' inside guest VM at \(guest).", type: .success)
    }

    private func unmountFolder(_ vmID: UUID, folderID: UUID) {
        try? VMSharedFolderManager.shared.removeSharedFolder(vmID: vmID, folderID: folderID)
        stateStore.refreshVM(vmID)
        stateStore.addLog("Unmounted host directory from guest filesystem.", type: .warning)
    }
}
