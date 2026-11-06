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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shared Directories & File Mounting")
                    .font(.headline)
                Text("Mount local directories from your host Mac into the virtual environment filesystem. This is perfect for executing active workspace code instantly inside Linux.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let vm = activeVM {
                GroupBox(label: Text("Share Local Folder").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mount Point Name")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                TextField("e.g. workspace", text: $folderName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Guest Target Path")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                TextField("/mnt/workspace", text: $guestMountPoint)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Local Mac Folder Path")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                TextField("Click Choose Folder or type path...", text: $hostPath)
                                    .textFieldStyle(.roundedBorder)

                                Button("Choose Folder...") {
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
                        }

                        HStack {
                            Toggle("Mount Read-Only", isOn: $isReadOnly)
                                .toggleStyle(.checkbox)
                            Spacer()
                            Button("Share Folder") {
                                mountFolder(vm.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(folderName.isEmpty || hostPath.isEmpty || guestMountPoint.isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox(label: Text("Shared Folders List").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        if vm.sharedFolders.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)

                                Text("No Shared Folders Configured")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Text("Share folder above so the guest Linux container can access host code repos or directories securely.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 420)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(vm.sharedFolders) { folder in
                                    HStack {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(.orange)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(folder.name)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                            Text("Mac Path: \(folder.hostPath) ➔ Guest: \(folder.guestMountPoint) \(folder.isReadOnly ? "(Read-Only)" : "(Read-Write)")")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Button(role: .destructive) {
                                            unmountFolder(vm.id, folderID: folder.id)
                                        } label: {
                                            Label("Stop Sharing", systemImage: "xmark.circle")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                    }
                                    .padding(.vertical, 8)

                                    if folder.id != vm.sharedFolders.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Share Folder Inline Help Info
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Linux Mounting Instructions")
                            .font(.caption)
                            .fontWeight(.bold)
                        Text("Shared directories are securely exposed via Apple Hypervisor's virtio-9p/virtio-fs drivers. If they do not mount automatically inside Linux, run the following shell command inside your guest terminal:\n'sudo mount -t 9p -o trans=virtio,version=9p2000.L <Mount_Name> /mnt/workspace'")
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
                    systemImage: "folder.badge.plus",
                    description: Text("Select an active environment from the sidebar to share directories.")
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
        stateStore.addLog("Mounted and shared host directory '\(name)' inside guest filesystem.", type: .success)
    }

    private func unmountFolder(_ vmID: UUID, folderID: UUID) {
        try? VMSharedFolderManager.shared.removeSharedFolder(vmID: vmID, folderID: folderID)
        stateStore.refreshVM(vmID)
        stateStore.addLog("Unmounted host shared folder directory from virtualization stack.", type: .warning)
    }
}
