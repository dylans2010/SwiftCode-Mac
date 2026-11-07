import Foundation

extension ConflictEditorState {

    public mutating func show(file: String?, document: MergeDocument?) {
        if let f = currentFile, f == file, self.document != nil { return }
        if let f = currentFile, f != file, let d = self.document { otherDocuments[f] = d }
        currentFile = file
        guard let file else { load(nil); return }
        load(otherDocuments.removeValue(forKey: file) ?? document)
    }

    public mutating func prefetch(file: String, document: MergeDocument?) {
        guard file != currentFile, otherDocuments[file] == nil, let document else { return }
        otherDocuments[file] = document
    }

    public func sheetDocument(_ file: String) -> MergeDocument? { file == currentFile ? document : otherDocuments[file] }

    public func isDecided(file: String) -> Bool { sheetDocument(file)?.isResolved ?? false }

    public var canMerge: Bool {
        guard source == .repository else { return false }
        if files.isEmpty { return integration.isInProgress }
        return files.allSatisfy(isDecided(file:))
    }

    public var primaryTitle: String {
        switch integration {
        case .merging: MergeSheetText.merge
        case .none: "Resolve"
        default: continueTitle
        }
    }

    public var resolutions: [(file: String, text: String)] {
        files.compactMap { f in sheetDocument(f).flatMap { $0.isResolved ? (f, $0.result) : nil } }
    }

    public mutating func chooseKeepingSelection(_ choice: MergeDocument.Choice) {
        guard var doc = document, let h = currentHunk else { return }
        doc.choose(choice, hunk: h)
        replaceDocument(doc)
    }

    public mutating func choose(_ choice: MergeDocument.Choice, forHunk h: Int) {
        selectHunk(h)
        chooseKeepingSelection(choice)
    }

    public var sheetRows: [MergeSheetRow] { document.map(MergeSheetLayout.rows) ?? [] }

    public var leftLines: [String] { document.map(MergeSheetLayout.leftText) ?? [] }
    public var rightLines: [String] { document.map { $0.chunks.flatMap(\.theirs) } ?? [] }

    public var stepperText: String {
        guard let doc = document, !doc.hunks.isEmpty else { return "0/0" }
        return "\((currentHunk ?? 0) + 1)/\(doc.hunks.count)"
    }

    public struct Token: Equatable, Sendable {
        public var glyph: String
        public var isDecided: Bool
        public var isSelected: Bool
        public var isConflict: Bool
    }

    public func token(forHunk h: Int) -> Token? {
        guard let doc = document, doc.hunks.indices.contains(h) else { return nil }
        let kind = doc.chunks[doc.hunks[h]].kind
        let choice = doc.choices[h]
        return Token(glyph: MergeSheetToken.glyph(choice: choice, kind: kind), isDecided: choice != .unresolved,
                     isSelected: h == currentHunk, isConflict: kind == .conflict)
    }

    public func rulerMarks(rows: [MergeSheetRow]) -> [(position: Double, isConflict: Bool)] {
        guard !rows.isEmpty else { return [] }
        return rows.enumerated().compactMap { i, r in r.isFirstOfHunk ? (Double(i) / Double(rows.count), r.kind == .conflict) : nil }
    }

    public struct FileRow: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case folder, file }
        public var kind: Kind
        public var title: String
        public var depth: Int
        public var path: String?
        public var isConflicted: Bool
    }

    public func fileRows(root: String, flat: Bool, filter: String = "") -> [FileRow] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = files.filter { needle.isEmpty || URL(fileURLWithPath: $0).lastPathComponent.lowercased().contains(needle) }
        func row(_ f: String, _ depth: Int) -> FileRow {
            FileRow(kind: .file, title: URL(fileURLWithPath: f).lastPathComponent, depth: depth, path: f, isConflicted: true)
        }
        if flat { return shown.map { row($0, 0) } }
        var out: [FileRow] = []
        var lastFolder: String?
        for f in shown.sorted() {
            let dir = (f as NSString).deletingLastPathComponent
            if dir != lastFolder {
                let name = dir == root ? URL(fileURLWithPath: root).lastPathComponent : (dir as NSString).lastPathComponent
                out.append(FileRow(kind: .folder, title: name, depth: 0, path: nil, isConflicted: false))
                lastFolder = dir
            }
            out.append(row(f, 1))
        }
        return out
    }

    public func jumpPath(root: String) -> [String] {
        guard let f = currentFile else { return [] }
        var parts = [URL(fileURLWithPath: root).lastPathComponent]
        let rel = f.hasPrefix(root + "/") ? String(f.dropFirst(root.count + 1)) : URL(fileURLWithPath: f).lastPathComponent
        let comps = rel.split(separator: "/").map(String.init)
        parts += comps.dropLast()
        if let last = comps.last { parts.append((last as NSString).deletingPathExtension) }
        return parts
    }
}

extension ConflictEditorState {
    mutating func replaceDocument(_ doc: MergeDocument) {
        let h = currentHunk
        load(doc)
        if let h { selectHunk(h) }
    }
}
