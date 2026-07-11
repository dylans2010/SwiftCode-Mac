import SwiftUI
import Combine

@MainActor
public final class ToolbarSettings: ObservableObject, Sendable {
    public static let shared = ToolbarSettings()

    @Published var wordWrap: Bool = false
    @Published var showSearchBar: Bool = false
    @AppStorage("com.swiftcode.toolbar.showToolNames") var showToolNames: Bool = true

    // Pinned Workspace Tools
    @Published public var pinnedTools: [String] = [] {
        didSet {
            savePinnedTools()
        }
    }

    private static let pinnedToolsKey = "com.swiftcode.pinnedTools"

    private init() {
        loadPinnedTools()
    }

    public func pinTool(id: String) {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return }
        if !pinnedTools.contains(cleanId) {
            withAnimation {
                pinnedTools.append(cleanId)
            }
        }
    }

    public func unpinTool(id: String) {
        if let index = pinnedTools.firstIndex(of: id) {
            withAnimation {
                pinnedTools.remove(at: index)
            }
        }
    }

    public func isPinned(id: String) -> Bool {
        pinnedTools.contains(id)
    }

    public func togglePin(id: String) {
        if isPinned(id: id) {
            unpinTool(id: id)
        } else {
            pinTool(id: id)
        }
    }

    public func movePinnedTool(from source: IndexSet, to destination: Int) {
        withAnimation {
            pinnedTools.move(fromOffsets: source, toOffset: destination)
        }
    }

    public func restorePinnedDefaults() {
        withAnimation {
            pinnedTools = ["deployments", "gist_manager", "source_control", "ai_code_gen"]
        }
    }

    private func savePinnedTools() {
        UserDefaults.standard.set(pinnedTools, forKey: Self.pinnedToolsKey)
    }

    private func loadPinnedTools() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.pinnedToolsKey) {
            pinnedTools = saved
        } else {
            restorePinnedDefaults()
        }
    }
}
