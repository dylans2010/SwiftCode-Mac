import SwiftUI

@MainActor
struct HomeProjectCardView: View {
    let project: Project
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showSymbolPopover = false
    @State private var showingSymbolPickerSheet = false

    private var projectSymbol: String {
        UserDefaults.standard.string(forKey: "com.swiftcode.project.symbol.\(project.id.uuidString)") ?? "swift"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                    Image(systemName: projectSymbol)
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
                .frame(width: 44, height: 44)
                .onHover { hovering in
                    if hovering {
                        showSymbolPopover = true
                    }
                }
                .popover(isPresented: $showSymbolPopover, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            showSymbolPopover = false
                            onDelete()
                        } label: {
                            Label("Delete Project", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)

                        Button {
                            showSymbolPopover = false
                            NotificationCenter.default.post(name: NSNotification.Name("com.swiftcode.project.addToFolder"), object: project)
                        } label: {
                            Label("Add to Folder", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.plain)

                        Button {
                            showSymbolPopover = false
                            showingSymbolPickerSheet = true
                        } label: {
                            Label("Change SF Symbol", systemImage: "sparkles")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                }

                Spacer()

                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                    .help("Delete Project")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(project.description.isEmpty ? "No description" : project.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack {
                Label {
                    Text(project.lastOpened, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if project.githubRepo != nil {
                    Image(systemName: "network")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding()
        .frame(width: 180, height: 150)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(isHovered ? 0.4 : 0.1), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect()
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHovered)
        .sheet(isPresented: $showingSymbolPickerSheet) {
            SimpleProjectSymbolPickerView(project: project)
        }
    }
}

struct SimpleProjectSymbolPickerView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var symbols: [String] = []
    @State private var searchQuery = ""

    var filteredSymbols: [String] {
        if searchQuery.isEmpty {
            return symbols.isEmpty ? ["swift", "folder", "star", "heart", "gear", "terminal", "hammer", "play", "app", "briefcase", "cpu", "globe"] : Array(symbols.prefix(150))
        }
        return symbols.filter { $0.localizedCaseInsensitiveContains(searchQuery) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Select Project Symbol")
                .font(.headline)
                .padding(.top)

            TextField("Search symbols...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 10) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        Button {
                            UserDefaults.standard.set(symbol, forKey: "com.swiftcode.project.symbol.\(project.id.uuidString)")
                            dismiss()
                        } label: {
                            VStack {
                                Image(systemName: symbol)
                                    .font(.title2)
                                    .frame(width: 40, height: 40)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
                .padding()
            }
        }
        .frame(width: 320, height: 380)
        .onAppear {
            let loaded = SFSymbolResourceLoader.shared.loadSymbols(version: 4)
            if !loaded.isEmpty {
                self.symbols = loaded.map { $0.name }
            }
        }
    }
}
