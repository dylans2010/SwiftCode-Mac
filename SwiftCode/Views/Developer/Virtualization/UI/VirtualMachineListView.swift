import SwiftUI

public struct VirtualMachineListView: View {
    @State private var stateStore = VirtualizationStateStore.shared

    // Library Filtering & Sorting States
    @State private var searchQuery: String = ""
    @State private var sortBy: SortOption = .name
    @State private var filterOS: String = "All"
    @State private var filterLabel: String = "All"
    @State private var filterSegment: LibrarySegment = .all

    // Popovers / Modals
    @State private var selectedVMForLabels: UUID? = nil
    @State private var labelInputText: String = ""
    @State private var showingLabelEditor = false
    @State private var showingEduSection = true

    public enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case createdDate = "Created Date"
        case status = "Status"
        case cpu = "CPU Cores"
        case ram = "RAM Sizing"
        case disk = "Disk Size"

        public var id: String { rawValue }
    }

    public enum LibrarySegment: String, CaseIterable, Identifiable {
        case all = "All Environments"
        case pinned = "Pinned"
        case favorites = "Favorites"
        case bookmarked = "Bookmarked"
        case recent = "Recent"

        public var id: String { rawValue }
    }

    private let availableLabels = [
        "Backend", "Testing", "Production", "Experimental", "Database", "AI", "Web", "Infrastructure"
    ]

    public init() {}

    // Filtered and Sorted list computation
    private var filteredAndSortedVMs: [VirtualMachine] {
        var list = stateStore.virtualMachines

        // 1. Text Search
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            list = list.filter { vm in
                vm.name.lowercased().contains(q) ||
                vm.osType.lowercased().contains(q) ||
                vm.labels.contains(where: { $0.lowercased().contains(q) })
            }
        }

        // 2. Segment Filters
        switch filterSegment {
        case .all:
            break
        case .pinned:
            list = list.filter { $0.isPinned }
        case .favorites:
            list = list.filter { $0.isFavorite }
        case .bookmarked:
            list = list.filter { $0.isBookmarked }
        case .recent:
            list = list.sorted { $0.uptime > $1.uptime }
        }

        // 3. OS Filter
        if filterOS != "All" {
            list = list.filter { $0.osType == filterOS }
        }

        // 4. Custom Label/Tag Filter
        if filterLabel != "All" {
            list = list.filter { $0.labels.contains(filterLabel) }
        }

        // 5. Sorting
        switch sortBy {
        case .name:
            list.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .createdDate:
            list.sort { $0.createdDate > $1.createdDate }
        case .status:
            list.sort { $0.status.rawValue < $1.status.rawValue }
        case .cpu:
            list.sort { $0.cpuCores > $1.cpuCores }
        case .ram:
            list.sort { $0.memoryMB > $1.memoryMB }
        case .disk:
            list.sort { $0.storageGB > $1.storageGB }
        }

        return list
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // LIBRARY FILTERS HEADER CARD
            GroupBox {
                VStack(spacing: 12) {
                    // Row 1: Search & Segmented Picker
                    HStack(spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search environments by name, OS, or tags...", text: $searchQuery)
                                .textFieldStyle(.plain)
                        }
                        .padding(6)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)

                        Picker("", selection: $filterSegment) {
                            ForEach(LibrarySegment.allCases) { seg in
                                Text(seg.rawValue).tag(seg)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 440)
                    }

                    Divider()

                    // Row 2: Sort, OS, Custom Labels Selectors
                    HStack(spacing: 16) {
                        HStack {
                            Text("Sort By:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $sortBy) {
                                ForEach(SortOption.allCases) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                            .frame(width: 120)
                        }

                        HStack {
                            Text("OS:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $filterOS) {
                                Text("All Operating Systems").tag("All")
                                Text("Ubuntu").tag("Ubuntu")
                                Text("Debian").tag("Debian")
                                Text("Fedora").tag("Fedora")
                                Text("Alpine").tag("Alpine")
                            }
                            .frame(width: 160)
                        }

                        HStack {
                            Text("Label/Tag:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $filterLabel) {
                                Text("All Labels").tag("All")
                                ForEach(availableLabels, id: \.self) { label in
                                    Text(label).tag(label)
                                }
                            }
                            .frame(width: 140)
                        }

                        Spacer()

                        Button {
                            searchQuery = ""
                            sortBy = .name
                            filterOS = "All"
                            filterLabel = "All"
                            filterSegment = .all
                        } label: {
                            Label("Reset Filters", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            // BRIEF CONTEXTUAL EDUCATION CARDS
            if showingEduSection {
                GroupBox {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "info.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("What is a Development Environment?")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Text("A Development Environment is an isolated guest VM sandbox designed to let you build backend microservices, run localized Docker networks, and test Python or Swift scripts safely, keeping host macOS completely clean.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)

                            HStack(spacing: 16) {
                                Button("Learn Snapshots...") {
                                    stateStore.addLog("Context: Snapshots capture live CPU/Disk blocks to allow instant rolling back.", type: .info)
                                }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)

                                Button("Why Shared Folders?") {
                                    stateStore.addLog("Context: Shared Folders mount host macOS directories inside /mnt/workspace dynamically.", type: .info)
                                }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                            }
                        }
                        Spacer()

                        Button {
                            showingEduSection = false
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }

            // ENVIRONMENTAL LIBRARY LIST
            if filteredAndSortedVMs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                        .padding(.top)

                    Text("No Matching Environments")
                        .font(.headline)

                    Text("No virtual sandboxes match your filter settings. Clear or adjust search queries to reveal configurations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            } else {
                ForEach(filteredAndSortedVMs) { vm in
                    HStack(spacing: 16) {
                        // Brand Icon for OS type
                        Image(systemName: osIcon(vm.osType))
                            .font(.system(size: 24))
                            .foregroundStyle(osColor(vm.osType))
                            .frame(width: 52, height: 52)
                            .background(osColor(vm.osType).opacity(0.1))
                            .cornerRadius(12)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center, spacing: 8) {
                                if vm.isPinned {
                                    Image(systemName: "pin.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                }

                                Text(vm.name)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)

                                statusBadge(for: vm.status)

                                ForEach(vm.labels, id: \.self) { label in
                                    Text(label.uppercased())
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundStyle(.blue)
                                        .cornerRadius(4)
                                }
                            }

                            // Subtitle resource details
                            HStack(spacing: 10) {
                                Text("\(vm.osType) \(vm.version)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text("•")
                                    .foregroundStyle(.secondary)

                                Label("\(vm.cpuCores) cores", systemImage: "cpu")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Label(String(format: "%.1f GB RAM", Double(vm.memoryMB) / 1024.0), systemImage: "memorychip")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Label("\(vm.storageGB) GB Disk", systemImage: "externaldrive")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // Startup Actions preview
                            if !vm.startupActions.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.right.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                    Text("On Startup: " + vm.startupActions.joined(separator: " ➔ "))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Spacer()

                        // INTERACTIVE QUICK TOGGLES (PIN, FAVORITE, BOOKMARK)
                        HStack(spacing: 8) {
                            Button {
                                togglePinned(vm.id)
                            } label: {
                                Image(systemName: vm.isPinned ? "pin.fill" : "pin")
                                    .foregroundStyle(vm.isPinned ? .orange : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Pin this environment to top of the sidebar")

                            Button {
                                toggleFavorite(vm.id)
                            } label: {
                                Image(systemName: vm.isFavorite ? "heart.fill" : "heart")
                                    .foregroundStyle(vm.isFavorite ? .red : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Mark this environment as a favorite")

                            Button {
                                toggleBookmarked(vm.id)
                            } label: {
                                Image(systemName: vm.isBookmarked ? "bookmark.fill" : "bookmark")
                                    .foregroundStyle(vm.isBookmarked ? .blue : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Bookmark this configuration")

                            Button {
                                openLabelEditorForVM(vm)
                            } label: {
                                Image(systemName: "tag.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Edit custom labels/tags")

                            Divider()
                                .frame(height: 24)

                            // Start/Stop Actions
                            if vm.status == .stopped || vm.status == .error {
                                Button {
                                    triggerStart(vm.id)
                                } label: {
                                    Label("Start", systemImage: "play.fill")
                                        .fontWeight(.medium)
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button {
                                    triggerStop(vm.id)
                                } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                        .fontWeight(.medium)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.bordered)
                            }

                            Button {
                                stateStore.selectedVMID = vm.id
                            } label: {
                                Text("Open Details")
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
            }
        }
        .sheet(isPresented: $showingLabelEditor) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "tag.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("Modify Environment Labels")
                        .font(.headline)
                    Spacer()
                    Button("Done") {
                        showingLabelEditor = false
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                Text("Select custom tags or enter new labels to categorize this development sandbox:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Enter label name (e.g. Frontend)...", text: $labelInputText, onCommit: addLabelFromInput)
                        .textFieldStyle(.roundedBorder)

                    Button("Add Label") {
                        addLabelFromInput()
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Preset label selectors using horizontal scrolling list of buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableLabels, id: \.self) { label in
                            Button {
                                toggleLabelOnSelectedVM(label)
                            } label: {
                                Text(label)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(hasLabel(label) ? Color.blue.opacity(0.15) : Color.primary.opacity(0.04))
                                    .foregroundStyle(hasLabel(label) ? .blue : .primary)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)

                Spacer()
            }
            .padding(20)
            .frame(width: 380, height: 280)
        }
    }

    @ViewBuilder
    private func statusBadge(for status: VMStatus) -> some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.12))
            .foregroundStyle(statusColor(status))
            .cornerRadius(4)
    }

    private func statusColor(_ status: VMStatus) -> Color {
        switch status {
        case .running: return .green
        case .starting: return .blue
        case .stopped: return .secondary
        case .pausing, .paused: return .orange
        case .stopping: return .orange
        case .error: return .red
        }
    }

    private func osIcon(_ type: String) -> String {
        switch type {
        case "Ubuntu": return "cpu"
        case "Debian": return "circle.circle"
        case "Fedora": return "shippingbox"
        case "Alpine": return "snowflake"
        default: return "terminal"
        }
    }

    private func osColor(_ type: String) -> Color {
        switch type {
        case "Ubuntu": return .orange
        case "Debian": return .red
        case "Fedora": return .blue
        case "Alpine": return .teal
        default: return .secondary
        }
    }

    private func triggerStart(_ id: UUID) {
        Task {
            let ctrl = SCVirtualizationEngine.shared.createController(for: id)
            await ctrl.start()
        }
    }

    private func triggerStop(_ id: UUID) {
        Task {
            let ctrl = SCVirtualizationEngine.shared.createController(for: id)
            await ctrl.stop()
        }
    }

    // Toggle logic functions
    private func togglePinned(_ id: UUID) {
        if let idx = stateStore.virtualMachines.firstIndex(where: { $0.id == id }) {
            stateStore.virtualMachines[idx].isPinned.toggle()
            try? VirtualMachineRegistry.shared.save(stateStore.virtualMachines)
            stateStore.addLog("Toggled pinned state for environment.", type: .info)
        }
    }

    private func toggleFavorite(_ id: UUID) {
        if let idx = stateStore.virtualMachines.firstIndex(where: { $0.id == id }) {
            stateStore.virtualMachines[idx].isFavorite.toggle()
            try? VirtualMachineRegistry.shared.save(stateStore.virtualMachines)
            stateStore.addLog("Toggled favorite state for environment.", type: .info)
        }
    }

    private func toggleBookmarked(_ id: UUID) {
        if let idx = stateStore.virtualMachines.firstIndex(where: { $0.id == id }) {
            stateStore.virtualMachines[idx].isBookmarked.toggle()
            try? VirtualMachineRegistry.shared.save(stateStore.virtualMachines)
            stateStore.addLog("Toggled bookmarked state for environment.", type: .info)
        }
    }

    private func openLabelEditorForVM(_ vm: VirtualMachine) {
        selectedVMForLabels = vm.id
        labelInputText = ""
        showingLabelEditor = true
    }

    private func hasLabel(_ label: String) -> Bool {
        guard let vmID = selectedVMForLabels,
              let vm = stateStore.virtualMachines.first(where: { $0.id == vmID }) else { return false }
        return vm.labels.contains(label)
    }

    private func toggleLabelOnSelectedVM(_ label: String) {
        guard let vmID = selectedVMForLabels,
              let idx = stateStore.virtualMachines.firstIndex(where: { $0.id == vmID }) else { return }

        if stateStore.virtualMachines[idx].labels.contains(label) {
            stateStore.virtualMachines[idx].labels.removeAll { $0 == label }
        } else {
            stateStore.virtualMachines[idx].labels.append(label)
        }
        try? VirtualMachineRegistry.shared.save(stateStore.virtualMachines)
    }

    private func addLabelFromInput() {
        let clean = labelInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        toggleLabelOnSelectedVM(clean)
        labelInputText = ""
    }
}
