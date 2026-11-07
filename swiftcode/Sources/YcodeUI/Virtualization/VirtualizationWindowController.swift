import AppKit
import Foundation

@MainActor
public final class VirtualizationWindowManager: NSObject {
    public static let shared = VirtualizationWindowManager()
    private var controller: VirtualizationWindowController?

    private override init() {}

    public func showWindow() {
        if let existing = controller {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = VirtualizationWindowController()
        self.controller = controller
        controller.window?.delegate = self
        controller.window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow() {
        controller?.close()
    }
}

extension VirtualizationWindowManager: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === controller?.window {
            controller = nil
        }
    }
}

@MainActor
public final class VirtualizationWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public static let size = NSSize(width: 1100, height: 750)

    public let registry: VirtualMachineRegistry

    private let vmTable = NSTableView()
    private let detailLabel = NSTextField(labelWithString: "")
    private let capabilityLabel = NSTextField(labelWithString: "")
    private let allocateButton = NSButton(title: "Allocate", target: nil, action: nil)
    private let releaseButton = NSButton(title: "Release", target: nil, action: nil)
    private let probeButton = NSButton(title: "Probe Host", target: nil, action: nil)
    private let createButton = NSButton(title: "Create VM…", target: nil, action: nil)
    private let duplicateButton = NSButton(title: "Duplicate", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)

    private var records: [VMRecord] = []
    private var selectedRecord: VMRecord?
    private var allocated: AllocatedVirtualMachine?

    public init(registry: VirtualMachineRegistry = .shared) {
        self.registry = registry
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Virtualization Console"
        window.minSize = NSSize(width: 900, height: 600)
        window.setFrameAutosaveName("SwiftCodeVirtualizationWindow")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let contentView = window?.contentView else { return }
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            split.topAnchor.constraint(equalTo: contentView.topAnchor),
            split.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let sidebar = NSView()
        let sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.spacing = 8
        sidebarStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)
        NSLayoutConstraint.activate([
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarStack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
        ])
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Virtual Machine"
        nameColumn.width = 240
        vmTable.addTableColumn(nameColumn)
        vmTable.dataSource = self
        vmTable.delegate = self
        vmTable.headerView = nil
        let tableScroll = NSScrollView()
        tableScroll.documentView = vmTable
        tableScroll.hasVerticalScroller = true
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        sidebarStack.addArrangedSubview(tableScroll)
        createButton.target = self
        createButton.action = #selector(createClicked)
        duplicateButton.target = self
        duplicateButton.action = #selector(duplicateClicked)
        duplicateButton.isEnabled = false
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.isEnabled = false
        let manageRow = NSStackView(views: [createButton, duplicateButton, deleteButton])
        manageRow.orientation = .horizontal
        manageRow.spacing = 8
        sidebarStack.addArrangedSubview(manageRow)
        sidebarStack.addArrangedSubview(NSView())

        let detail = NSView()
        let detailStack = NSStackView()
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 10
        detailStack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(detailStack)
        NSLayoutConstraint.activate([
            detailStack.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            detailStack.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            detailStack.topAnchor.constraint(equalTo: detail.topAnchor),
        ])
        capabilityLabel.font = .systemFont(ofSize: 11)
        capabilityLabel.textColor = .secondaryLabelColor
        capabilityLabel.stringValue = "Host capability: not probed yet."
        detailStack.addArrangedSubview(capabilityLabel)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.lineBreakMode = .byWordWrapping
        detailStack.addArrangedSubview(detailLabel)
        allocateButton.target = self
        allocateButton.action = #selector(allocateClicked)
        allocateButton.isEnabled = false
        releaseButton.target = self
        releaseButton.action = #selector(releaseClicked)
        releaseButton.isEnabled = false
        probeButton.target = self
        probeButton.action = #selector(probeClicked)
        let actionRow = NSStackView(views: [allocateButton, releaseButton, probeButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8
        detailStack.addArrangedSubview(actionRow)
        let note = NSTextField(labelWithString: "Allocate reserves a real KVM VM (RAM + vCPUs) and holds it; Release closes it. No guest kernel is loaded and there is no display — booting a guest, snapshots, and networking need a Virtualization.framework wrapper on macOS or a kernel-boot path on KVM, and are not available here.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.lineBreakMode = .byWordWrapping
        note.translatesAutoresizingMaskIntoConstraints = false
        note.widthAnchor.constraint(equalToConstant: 640).isActive = true
        detailStack.addArrangedSubview(note)

        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(detail)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
    }

    func reload() {
        records = registry.all()
        vmTable.reloadData()
        updateDetail()
    }

    private func updateDetail() {
        guard let record = selectedRecord else {
            detailLabel.stringValue = "Select a virtual machine, or create one."
            allocateButton.isEnabled = false
            releaseButton.isEnabled = false
            duplicateButton.isEnabled = false
            deleteButton.isEnabled = false
            return
        }
        let allocatedHere = allocated?.record.id == record.id
        detailLabel.stringValue = """
        \(record.name)
        OS: \(record.osType) \(record.version)
        Status: \(allocatedHere ? "Allocated (KVM VM held)" : record.status)
        CPU: \(record.cpuCores) core\(record.cpuCores == 1 ? "" : "s") · Memory: \(record.memoryMB) MB · Storage: \(record.storageGB) GB
        Disk image: \(record.imagePath.isEmpty ? "none" : record.imagePath)
        Created: \(record.createdDate.formatted(date: .abbreviated, time: .shortened)) · Boots: \(record.bootCount)
        """
        allocateButton.isEnabled = !allocatedHere
        releaseButton.isEnabled = allocatedHere
        duplicateButton.isEnabled = true
        deleteButton.isEnabled = true
    }

    @objc private func createClicked() {
        let panel = NSAlert()
        panel.messageText = "Create Virtual Machine"
        panel.informativeText = "A definition in the registry — it does not boot a guest. Pick an OS and resources; the disk image is optional."
        let nameField = NSTextField(frame: NSRect(x: 0, y: 66, width: 280, height: 24))
        nameField.placeholderString = "Name (e.g. Ubuntu Dev)"
        let osPopup = NSPopUpButton(frame: NSRect(x: 0, y: 36, width: 280, height: 24))
        osPopup.addItems(withTitles: VMRecord.knownOSTypes)
        let memoryField = NSTextField(frame: NSRect(x: 0, y: 6, width: 280, height: 24))
        memoryField.placeholderString = "Memory in MB (default 2048)"
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 96))
        accessory.addSubview(nameField)
        accessory.addSubview(osPopup)
        accessory.addSubview(memoryField)
        panel.accessoryView = accessory
        panel.addButton(withTitle: "Create")
        panel.addButton(withTitle: "Cancel")
        guard panel.runModal() == .alertFirstButtonReturn else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let memoryMB = Int(memoryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 2048
        do {
            let record = try registry.create(name: name, osType: osPopup.titleOfSelectedItem ?? "Ubuntu", memoryMB: memoryMB)
            reload()
            if let row = records.firstIndex(where: { $0.id == record.id }) {
                vmTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        } catch {
            capabilityLabel.stringValue = "Could not create the VM: \(error.localizedDescription)"
        }
    }

    @objc private func duplicateClicked() {
        guard let record = selectedRecord else { return }
        do {
            let copy = try registry.duplicate(id: record.id)
            reload()
            if let row = records.firstIndex(where: { $0.id == copy.id }) {
                vmTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        } catch {
            capabilityLabel.stringValue = "Could not duplicate the VM: \(error.localizedDescription)"
        }
    }

    @objc private func deleteClicked() {
        guard let record = selectedRecord else { return }
        if allocated?.record.id == record.id { allocated?.release(); allocated = nil }
        do {
            try registry.delete(id: record.id)
            selectedRecord = nil
            reload()
        } catch {
            capabilityLabel.stringValue = "Could not delete the VM: \(error.localizedDescription)"
        }
    }

    @objc private func allocateClicked() {
        guard let record = selectedRecord else { return }
        let allocation = AllocatedVirtualMachine(record: record)
        do {
            try allocation.allocate()
            allocated = allocation
            try registry.updateStatus(id: record.id, status: "Allocated")
            capabilityLabel.stringValue = "Allocated a KVM VM for \(record.name): \(record.cpuCores) vCPU(s), \(record.memoryMB) MB RAM held. No guest kernel is loaded."
            reload()
        } catch {
            capabilityLabel.stringValue = "Allocation failed for \(record.name): \(error)"
        }
    }

    @objc private func releaseClicked() {
        guard let record = selectedRecord else { return }
        allocated?.release()
        allocated = nil
        do {
            try registry.updateStatus(id: record.id, status: "Stopped")
        } catch {
            capabilityLabel.stringValue = "Could not update the VM status: \(error.localizedDescription)"
        }
        capabilityLabel.stringValue = "Released the KVM VM for \(record.name)."
        reload()
    }

    @objc private func probeClicked() {
        probeButton.isEnabled = false
        capabilityLabel.stringValue = "Probing the host hypervisor (allocating a test VM)..."
        Task.detached {
            let result = VirtualMachineHostProbeRunner.probe()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.probeButton.isEnabled = true
                if let error = result.error {
                    self.capabilityLabel.stringValue = error
                } else {
                    self.capabilityLabel.stringValue = "Host hypervisor available: allocated a test VM with \(result.vcpusAllocated) vCPU and \(result.ramBytesAllocated / (1 << 20)) MB RAM, then released it."
                }
            }
        }
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { records.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard records.indices.contains(row) else { return nil }
        let record = records[row]
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: record.name)
        field.font = .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
        cell.textField = field
        cell.addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = vmTable.selectedRow
        selectedRecord = row >= 0 && records.indices.contains(row) ? records[row] : nil
        updateDetail()
    }
}
