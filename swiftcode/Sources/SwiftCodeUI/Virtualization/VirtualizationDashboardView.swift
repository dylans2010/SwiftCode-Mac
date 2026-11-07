import SwiftUI
import AppKit

public struct VirtualizationDashboardView: View {
    @State private var records: [VMRecord] = []
    @State private var selectedVMID: UUID?
    @State private var hostProbeStatus: String = "Host capability: not probed yet."
    @State private var isProbing = false
    @State private var showCreateSheet = false

    private let registry = VirtualMachineRegistry.shared

    public init() {}

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(records, selection: $selectedVMID) { vm in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(vm.name)
                                .font(.headline)
                            Spacer()
                            Text(vm.status)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(statusColor(vm.status).opacity(0.15), in: Capsule())
                                .foregroundStyle(statusColor(vm.status))
                        }
                        Text("\(vm.osType) · \(vm.cpuCores) vCPU · \(vm.memoryMB) MB RAM")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: 8) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("New VM", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        registry.scanVirtualDiskFiles()
                        reload()
                    } label: {
                        Label("Scan Disks", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }
                .padding(10)
            }
            .navigationTitle("Virtual Machines")
        } detail: {
            if let selected = records.first(where: { $0.id == selectedVMID }) {
                vmDetailView(for: selected)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a virtual machine or create a new one.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    probeHost()
                } label: {
                    Label("Probe Hypervisor", systemImage: "cpu")
                }
                .disabled(isProbing)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateVirtualMachineSheet { newRecord in
                reload()
                selectedVMID = newRecord.id
            }
        }
        .onAppear {
            reload()
        }
    }

    @ViewBuilder
    private func vmDetailView(for vm: VMRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.name)
                            .font(.title.bold())
                        Text("Operating System: \(vm.osType) \(vm.version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(vm.status)
                        .font(.callout.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statusColor(vm.status).opacity(0.15), in: Capsule())
                        .foregroundStyle(statusColor(vm.status))
                }

                Divider()

                GroupBox("Resource Allocation") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("CPU Cores:").foregroundStyle(.secondary)
                            Text("\(vm.cpuCores) vCPU")
                        }
                        GridRow {
                            Text("Memory:").foregroundStyle(.secondary)
                            Text("\(vm.memoryMB) MB")
                        }
                        GridRow {
                            Text("Disk Storage:").foregroundStyle(.secondary)
                            Text("\(vm.storageGB) GB")
                        }
                        GridRow {
                            Text("Disk Image:").foregroundStyle(.secondary)
                            Text(vm.imagePath.isEmpty ? "None configured" : vm.imagePath)
                                .font(.caption.monospaced())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                GroupBox("Status & Diagnostics") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(hostProbeStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Created: \(vm.createdDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Boot cycles: \(vm.bootCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                HStack(spacing: 12) {
                    Button("Allocate VM") {
                        allocate(vm)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Release VM") {
                        release(vm)
                    }
                    .buttonStyle(.bordered)

                    Button("Duplicate") {
                        if let copy = try? registry.duplicate(id: vm.id) {
                            reload()
                            selectedVMID = copy.id
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(role: .destructive) {
                        try? registry.delete(id: vm.id)
                        selectedVMID = nil
                        reload()
                    } label: {
                        Text("Delete VM")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "running", "allocated": return .green
        case "stopped": return .secondary
        case "image missing": return .red
        default: return .orange
        }
    }

    private func reload() {
        records = registry.all()
    }

    private func probeHost() {
        isProbing = true
        hostProbeStatus = "Probing host hypervisor..."
        Task.detached {
            let result = VirtualMachineHostProbeRunner.probe()
            await MainActor.run {
                isProbing = false
                if let error = result.error {
                    hostProbeStatus = error
                } else {
                    hostProbeStatus = "Host hypervisor available: allocated test VM (\(result.vcpusAllocated) vCPU, \(result.ramBytesAllocated / (1 << 20)) MB RAM)."
                }
            }
        }
    }

    private func allocate(_ vm: VMRecord) {
        let allocation = AllocatedVirtualMachine(record: vm)
        do {
            try allocation.allocate()
            try registry.updateStatus(id: vm.id, status: "Allocated")
            hostProbeStatus = "Allocated VM \(vm.name): \(vm.cpuCores) vCPU, \(vm.memoryMB) MB RAM."
            reload()
        } catch {
            hostProbeStatus = "Allocation failed: \(error.localizedDescription)"
        }
    }

    private func release(_ vm: VMRecord) {
        do {
            try registry.updateStatus(id: vm.id, status: "Stopped")
            hostProbeStatus = "Released VM \(vm.name)."
            reload()
        } catch {
            hostProbeStatus = "Release failed: \(error.localizedDescription)"
        }
    }
}

struct CreateVirtualMachineSheet: View {
    var onCreated: (VMRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var osType = "Ubuntu"
    @State private var cpuCores = 2
    @State private var memoryMB = 2048
    @State private var storageGB = 20
    @State private var imagePath = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("VM Name", text: $name)
                    Picker("Operating System", selection: $osType) {
                        ForEach(VMRecord.knownOSTypes, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }

                Section("Hardware Configuration") {
                    Stepper("CPU Cores: \(cpuCores)", value: $cpuCores, in: 1...16)
                    Stepper("RAM: \(memoryMB) MB", value: $memoryMB, in: 512...32768, step: 512)
                    Stepper("Storage: \(storageGB) GB", value: $storageGB, in: 5...500, step: 5)
                }

                Section("Disk Image (Optional)") {
                    HStack {
                        TextField("Image Path", text: $imagePath)
                        Button("Browse…") {
                            let openPanel = NSOpenPanel()
                            openPanel.canChooseFiles = true
                            openPanel.canChooseDirectories = false
                            openPanel.allowsMultipleSelection = false
                            if openPanel.runModal() == .OK, let url = openPanel.url {
                                imagePath = url.path
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Virtual Machine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        create()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 380)
    }

    private func create() {
        do {
            let record = try VirtualMachineRegistry.shared.create(
                name: name.trimmingCharacters(in: .whitespaces),
                osType: osType,
                cpuCores: cpuCores,
                memoryMB: memoryMB,
                storageGB: storageGB,
                imagePath: imagePath
            )
            onCreated(record)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


@MainActor
public final class VirtualizationDashboardWindowController: NSWindowController {
    public static let shared = VirtualizationDashboardWindowController()

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 950, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Virtualization Management Studio"
        window.center()
        window.setFrameAutosaveName("SwiftCodeVirtualizationDashboardWindow")
        window.contentView = NSHostingView(rootView: VirtualizationDashboardView())
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
