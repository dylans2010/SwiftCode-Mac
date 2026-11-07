import Combine
import Foundation

public enum SDKCodeEditorError: Error, Sendable {
    case unreadableFile(url: URL, reason: String)
}

public struct SDKCodeNavigationTarget: Equatable, Sendable {
    public let id: UUID
    public let tabID: UUID
    public let line: Int
    public let column: Int?

    public init(id: UUID = UUID(), tabID: UUID, line: Int, column: Int? = nil) {
        self.id = id
        self.tabID = tabID
        self.line = max(1, line)
        self.column = column
    }
}

public struct SDKEditorDiagnostic: Identifiable, Equatable, Sendable, Hashable {
    public enum Severity: String, Sendable, Codable, Hashable {
        case error
        case warning
        case info
    }

    public let id: UUID
    public let severity: Severity
    public let source: String
    public let code: String
    public let message: String
    public let suggestion: String?
    public let fileURL: URL?
    public let line: Int?
    public let column: Int?

    public init(
        id: UUID = UUID(),
        severity: Severity,
        source: String,
        code: String,
        message: String,
        suggestion: String? = nil,
        fileURL: URL? = nil,
        line: Int? = nil,
        column: Int? = nil
    ) {
        self.id = id
        self.severity = severity
        self.source = source
        self.code = code
        self.message = message
        self.suggestion = suggestion
        self.fileURL = fileURL
        self.line = line
        self.column = column
    }
}

@MainActor
public final class SDKCodeEditorState: ObservableObject {
    public static let maxConsoleEntries: Int = 5_000

    private static let persistedProjectRootKey = "com.swiftcode.sdk.studio.codeEditor.projectRootPath"

    @Published public private(set) var tabs: [SDKCodeEditorTab] = []

    @Published public private(set) var activeTabID: UUID?

    @Published public private(set) var consoleEntries: [SDKConsoleEntry] = []

    @Published public private(set) var diagnostics: [SDKEditorDiagnostic] = []

    @Published public var findQuery: String = ""

    @Published public var projectRootURL: URL? {
        didSet {
            if let root = projectRootURL {
                UserDefaults.standard.set(root.standardizedFileURL.path, forKey: Self.persistedProjectRootKey)
                UserDefaults.standard.synchronize()
            } else {
                UserDefaults.standard.removeObject(forKey: Self.persistedProjectRootKey)
                UserDefaults.standard.synchronize()
            }
        }
    }

    @Published public var requestedNavigationTarget: SDKCodeNavigationTarget?

    @Published public var externalModificationTabIDs: Set<UUID> = []

    public init(projectRootURL: URL? = nil) {
        if let explicitRoot = projectRootURL {
            self.projectRootURL = explicitRoot.standardizedFileURL
        } else if let savedPath = UserDefaults.standard.string(forKey: Self.persistedProjectRootKey),
                  FileManager.default.fileExists(atPath: savedPath) {
            self.projectRootURL = URL(fileURLWithPath: savedPath).standardizedFileURL
        } else {
            self.projectRootURL = nil
        }
    }

    public func setProjectRoot(_ url: URL?) {
        projectRootURL = url?.standardizedFileURL
    }

    public var activeTab: SDKCodeEditorTab? {
        guard let activeTabID else { return nil }
        return tabs.first(where: { $0.id == activeTabID })
    }

    public var activeDocument: SDKCodeDocument? {
        activeTab?.document
    }

    public var hasUnsavedChanges: Bool {
        tabs.contains(where: { $0.document.isDirty })
    }

    @discardableResult
    public func openTab(for document: SDKCodeDocument) -> UUID {
        if let existingIndex = indexOfTab(matching: document) {
            let id = tabs[existingIndex].id
            activateTab(id)
            return id
        }
        var docWithTimestamp = document
        if let url = document.fileURL, docWithTimestamp.lastKnownModificationDate == nil {
            docWithTimestamp = SDKCodeDocument(
                id: document.id,
                fileURL: url,
                language: document.language,
                text: document.text,
                isDirty: document.isDirty,
                cursorOffset: document.cursorOffset,
                lastKnownModificationDate: diskModificationDate(for: url),
                hasExternalModification: false
            )
        }
        let newTab = SDKCodeEditorTab(document: docWithTimestamp, isActive: true)
        tabs.append(newTab)
        activateTab(newTab.id)
        return newTab.id
    }

    @discardableResult
    public func openFile(_ url: URL) throws -> UUID {
        if let existing = tabs.first(where: {
            $0.document.fileURL == url || $0.document.fileURL?.standardizedFileURL == url.standardizedFileURL
        }) {
            activateTab(existing.id)
            return existing.id
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SDKCodeEditorError.unreadableFile(url: url, reason: error.localizedDescription)
        }
        let document = SDKCodeDocument(
            fileURL: url,
            language: SDKCodeLanguage.infer(fromFileURL: url),
            text: text,
            isDirty: false,
            lastKnownModificationDate: diskModificationDate(for: url)
        )
        let tab = SDKCodeEditorTab(document: document)
        tabs.append(tab)
        activateTab(tab.id)
        return tab.id
    }

    @discardableResult
    public func openFile(at url: URL) throws -> UUID {
        try openFile(url)
    }

    @discardableResult
    public func newUntitledTab(language: SDKCodeLanguage = .typescript, initialText: String = "") -> UUID {
        let doc = SDKCodeDocument(
            fileURL: nil,
            language: language,
            text: initialText,
            isDirty: !initialText.isEmpty
        )
        return openTab(for: doc)
    }

    public func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        externalModificationTabIDs.remove(id)
        guard activeTabID == id else { return }
        if tabs.isEmpty {
            activeTabID = nil
        } else {
            let nextIndex = min(index, tabs.count - 1)
            activateTab(tabs[nextIndex].id)
        }
    }

    public func activateTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        tabs = tabs.map { $0.withActive($0.id == id) }
    }

    public func updateText(_ text: String, for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index] = tabs[index].withDocument(tabs[index].document.withText(text))
    }

    public func markSaved(tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let modDate = tabs[index].document.fileURL.flatMap { diskModificationDate(for: $0) }
        tabs[index] = tabs[index].withDocument(
            tabs[index].document.saved(
                fileURL: tabs[index].document.fileURL,
                modificationDate: modDate
            )
        )
        externalModificationTabIDs.remove(tabID)
    }

    public func retargetTab(_ tabID: UUID, to destinationURL: URL) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let standardized = destinationURL.standardizedFileURL
        let modDate = diskModificationDate(for: standardized)
        let savedDoc = tabs[index].document.saved(fileURL: standardized, modificationDate: modDate)
        tabs[index] = tabs[index].withDocument(savedDoc)
        externalModificationTabIDs.remove(tabID)
    }

    public func updateActiveDocument(_ transform: (SDKCodeDocument) -> SDKCodeDocument) {
        guard let activeTabID else { return }
        updateDocument(forTab: activeTabID, transform)
    }

    public func updateDocument(
        forTab tabID: UUID,
        _ transform: (SDKCodeDocument) -> SDKCodeDocument
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let updated = transform(tabs[index].document)
        tabs[index] = tabs[index].withDocument(updated)
    }

    public func saveAllModifiedTabs() {
        for index in tabs.indices {
            let doc = tabs[index].document
            guard doc.isDirty, let url = doc.fileURL else { continue }
            do {
                try Data(doc.text.utf8).write(to: url, options: .atomic)
                let modDate = diskModificationDate(for: url)
                tabs[index] = tabs[index].withDocument(doc.saved(fileURL: url, modificationDate: modDate))
                externalModificationTabIDs.remove(tabs[index].id)
            } catch {
                appendConsole(SDKConsoleEntry(
                    stream: .stderr,
                    text: "Failed to save \(url.lastPathComponent): \(error.localizedDescription)"
                ))
            }
        }
    }

    public func checkExternalModifications() {
        for index in tabs.indices {
            let tab = tabs[index]
            let doc = tab.document
            guard let url = doc.fileURL else { continue }
            guard let diskDate = diskModificationDate(for: url) else { continue }
            if let knownDate = doc.lastKnownModificationDate, diskDate > knownDate.addingTimeInterval(0.5) {
                guard let diskData = try? Data(contentsOf: url),
                      let diskText = String(data: diskData, encoding: .utf8) else { continue }
                if diskText != doc.text {
                    if !doc.isDirty {
                        let reloaded = SDKCodeDocument(
                            id: doc.id,
                            fileURL: url,
                            language: doc.language,
                            text: diskText,
                            isDirty: false,
                            cursorOffset: doc.cursorOffset,
                            lastKnownModificationDate: diskDate,
                            hasExternalModification: false
                        )
                        tabs[index] = tab.withDocument(reloaded)
                        externalModificationTabIDs.remove(tab.id)
                    } else {
                        tabs[index] = tab.withDocument(doc.withExternalModification(true))
                        externalModificationTabIDs.insert(tab.id)
                    }
                } else {
                    tabs[index] = tab.withDocument(doc.saved(fileURL: url, modificationDate: diskDate))
                }
            }
        }
    }

    public func reloadTabFromDisk(_ tabID: UUID) throws {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let url = tabs[index].document.fileURL else { return }
        let data = try Data(contentsOf: url)
        guard let diskText = String(data: data, encoding: .utf8) else { return }
        let doc = tabs[index].document
        let reloaded = SDKCodeDocument(
            id: doc.id,
            fileURL: url,
            language: doc.language,
            text: diskText,
            isDirty: false,
            cursorOffset: nil,
            lastKnownModificationDate: diskModificationDate(for: url),
            hasExternalModification: false
        )
        tabs[index] = tabs[index].withDocument(reloaded)
        externalModificationTabIDs.remove(tabID)
    }

    public func dismissExternalModification(for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let doc = tabs[index].document
        let diskDate = doc.fileURL.flatMap { diskModificationDate(for: $0) } ?? doc.lastKnownModificationDate
        let updated = SDKCodeDocument(
            id: doc.id,
            fileURL: doc.fileURL,
            language: doc.language,
            text: doc.text,
            isDirty: true,
            cursorOffset: doc.cursorOffset,
            lastKnownModificationDate: diskDate,
            hasExternalModification: false
        )
        tabs[index] = tabs[index].withDocument(updated)
        externalModificationTabIDs.remove(tabID)
    }

    public func insertCodeSnippet(
        _ snippetCode: String,
        preferredLanguage: SDKCodeLanguage = .typescript,
        suggestedTitle: String? = nil
    ) {
        let trimmed = snippetCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let activeID = activeTabID,
           let index = tabs.firstIndex(where: { $0.id == activeID }),
           !(tabs[index].document.displayName == "swiftcode.json" && preferredLanguage != .json) {
            let doc = tabs[index].document
            let updatedText: String
            if doc.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updatedText = trimmed + "\n"
            } else if let offset = doc.cursorOffset,
                      offset >= 0,
                      offset <= doc.text.utf16.count,
                      offset <= doc.text.utf16.count {
                var mutable = doc.text
                let insertion = "\n" + trimmed + "\n"
                mutable.insert(contentsOf: insertion, at: String.Index(utf16Offset: offset, in: doc.text))
                updatedText = mutable
            } else {
                var mutable = doc.text
                if !mutable.hasSuffix("\n") { mutable += "\n" }
                mutable += "\n" + trimmed + "\n"
                updatedText = mutable
            }
            tabs[index] = tabs[index].withDocument(doc.withText(updatedText))
            appendConsole(SDKConsoleEntry(
                stream: .system,
                text: "Inserted snippet into \(doc.displayName)"
            ))
            return
        }

        if preferredLanguage == .typescript, let root = projectRootURL {
            let indexTS = root.appendingPathComponent("src/index.ts")
            if FileManager.default.fileExists(atPath: indexTS.path),
               let tabID = try? openFile(indexTS),
               let idx = tabs.firstIndex(where: { $0.id == tabID }) {
                let doc = tabs[idx].document
                var mutable = doc.text
                if !mutable.hasSuffix("\n") { mutable += "\n" }
                mutable += "\n" + trimmed + "\n"
                tabs[idx] = tabs[idx].withDocument(doc.withText(mutable))
                appendConsole(SDKConsoleEntry(
                    stream: .system,
                    text: "Inserted snippet into src/index.ts"
                ))
                return
            }
        }

        let newDoc = SDKCodeDocument(
            fileURL: nil,
            language: preferredLanguage,
            text: trimmed + "\n",
            isDirty: true
        )
        _ = openTab(for: newDoc)
        appendConsole(SDKConsoleEntry(
            stream: .system,
            text: "Opened new \(preferredLanguage.displayName) buffer with snippet"
        ))
    }

    @discardableResult
    public func addCapabilityToManifest(capabilityId: String, reason: String) -> Bool {
        guard let root = projectRootURL else { return false }
        let manifestURL = root.appendingPathComponent("swiftcode.json").standardizedFileURL
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONDecoder().decode(SDKManifest.self, from: data) else {
            return false
        }

        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Required for \(capabilityId)"
            : reason.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existingIdx = manifest.capabilities.firstIndex(where: { $0.id == capabilityId }) {
            manifest.capabilities[existingIdx].reason = cleanReason
        } else {
            manifest.capabilities.append(SDKManifestCapability(id: capabilityId, reason: cleanReason))
        }

        guard let encoded = try? manifest.encodedPrettyString() else { return false }
        do {
            try Data(encoded.utf8).write(to: manifestURL, options: .atomic)
            let modDate = diskModificationDate(for: manifestURL)
            if let idx = tabs.firstIndex(where: { $0.document.fileURL?.standardizedFileURL == manifestURL }) {
                let doc = tabs[idx].document.withText(encoded).saved(fileURL: manifestURL, modificationDate: modDate)
                tabs[idx] = tabs[idx].withDocument(doc)
            }
            appendConsole(SDKConsoleEntry(
                stream: .system,
                text: "Added capability \"\(capabilityId)\" to swiftcode.json"
            ))
            return true
        } catch {
            return false
        }
    }

    public func navigateTo(fileURL: URL, line: Int, column: Int? = nil) {
        guard let tabID = try? openFile(fileURL) else { return }
        requestedNavigationTarget = SDKCodeNavigationTarget(
            tabID: tabID,
            line: line,
            column: column
        )
    }

    public func navigateActiveTabTo(line: Int, column: Int? = nil) {
        guard let activeTabID else { return }
        requestedNavigationTarget = SDKCodeNavigationTarget(
            tabID: activeTabID,
            line: line,
            column: column
        )
    }

    public func clearNavigationTarget() {
        requestedNavigationTarget = nil
    }

    public func setDiagnostics(_ items: [SDKEditorDiagnostic]) {
        diagnostics = items
    }

    public func appendDiagnostic(_ item: SDKEditorDiagnostic) {
        if !diagnostics.contains(where: {
            $0.fileURL == item.fileURL &&
            $0.line == item.line &&
            $0.code == item.code &&
            $0.message == item.message
        }) {
            diagnostics.append(item)
        }
    }

    public func clearDiagnostics() {
        diagnostics.removeAll()
    }

    public func appendConsole(_ entry: SDKConsoleEntry) {
        var text = entry.text
        if text.count > SDKConsoleEntry.maxTextLength {
            text = String(text.prefix(SDKConsoleEntry.maxTextLength)) + "… (truncated)"
        }
        let bounded = text == entry.text
            ? entry
            : SDKConsoleEntry(id: entry.id, timestamp: entry.timestamp, stream: entry.stream, text: text)
        consoleEntries.append(bounded)
        let overflow = consoleEntries.count - Self.maxConsoleEntries
        if overflow > 0 {
            consoleEntries.removeFirst(overflow)
        }
    }

    public func clearConsole() {
        consoleEntries.removeAll()
    }

    private func indexOfTab(matching document: SDKCodeDocument) -> Int? {
        if let targetURL = document.fileURL?.standardizedFileURL {
            return tabs.firstIndex {
                $0.document.fileURL?.standardizedFileURL == targetURL
            }
        }
        return tabs.firstIndex { $0.document.id == document.id }
    }

    private func diskModificationDate(for url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
