import Foundation
import Observation
import YcodeIDECore
import YcodePlist

@MainActor
@Observable
public final class PlistEditorModel {
    public let path: String
    public private(set) var document: PropertyListDocument
    public private(set) var tree: PlistTree
    public private(set) var expanded: Set<[Int]>
    public var selection: [Int]?
    public var showsRawKeys = false
    public private(set) var sortColumn: PlistTree.SortColumn?
    public private(set) var sortAscending = true
    public private(set) var problem: String?
    public private(set) var saveCount = 0

    public init(path: String) throws {
        self.path = path
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let d = try PropertyListDocument(data: data)
        document = d
        tree = PlistTree(root: d.root)
        expanded = Self.initiallyExpanded(d.root)
    }

    static func initiallyExpanded(_ root: PropertyListItem) -> Set<[Int]> {
        var out: Set<[Int]> = [[]]
        for (i, kid) in PlistTree.children(of: root).enumerated() where PlistTree.isContainer(kid.value) && PlistTree.children(of: kid.value).count <= 12 {
            out.insert([i])
        }
        return out
    }

    public var formatName: String {
        switch document.format {
        case .xml: "XML Property List"
        case .binary: "Binary Property List"
        case .openStep: "OpenStep Property List"
        }
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public var path: [Int]
        public var depth: Int
        public var key: String
        public var rawKey: String?
        public var type: String
        public var value: String
        public var isContainer: Bool
        public var isExpanded: Bool
        public var hasChildren: Bool
        public var isKeyEditable: Bool { rawKey != nil }
        public var isValueEditable: Bool { !isContainer }
        public var id: String { path.isEmpty ? "root" : path.map(String.init).joined(separator: ".") }
    }

    public var rows: [Row] {
        var out: [Row] = []
        func add(_ v: PropertyListItem, path: [Int], depth: Int, key: String, rawKey: String?) {
            let container = PlistTree.isContainer(v)
            let open = container && expanded.contains(path)
            out.append(Row(path: path, depth: depth, key: key, rawKey: rawKey, type: v.typeName,
                           value: container ? v.summary : PlistTree.editText(v), isContainer: container, isExpanded: open,
                           hasChildren: container && !PlistTree.children(of: v).isEmpty))
            guard open else { return }
            let kids = PlistTree.children(of: v)
            let isDictionary: Bool = { if case .dictionary = v { return true } else { return false } }()
            for i in PlistTree.displayOrder(of: v, by: sortColumn, ascending: sortAscending) {
                let k = kids[i].key
                add(kids[i].value, path: path + [i], depth: depth + 1, key: isDictionary ? displayedKey(k) : k, rawKey: isDictionary ? k : nil)
            }
        }
        add(tree.root, path: [], depth: 0, key: "Root", rawKey: nil)
        return out
    }

    public func displayedKey(_ key: String) -> String { showsRawKeys ? key : ProjectEditorModel.readableKey(key) }

    public func rawKey(forDisplayed text: String, current: String) -> String {
        if text == displayedKey(current) { return current }
        return ProjectEditorModel.readableInfoKeys.first { $0.value == text }?.key ?? text
    }

    public func isExpanded(_ path: [Int]) -> Bool { expanded.contains(path) }

    public func setExpanded(_ path: [Int], _ on: Bool) {
        if on { expanded.insert(path) } else { expanded = expanded.filter { !$0.starts(with: path) || $0.count < path.count } }
    }

    public func sort(by column: PlistTree.SortColumn) {
        if sortColumn != column {
            sortColumn = column
            sortAscending = true
        } else if sortAscending {
            sortAscending = false
        } else {
            sortColumn = nil
            sortAscending = true
        }
    }

    @discardableResult
    public func setKey(_ text: String, at path: [Int]) -> Bool {
        guard let last = path.last, let parent = tree.item(at: Array(path.dropLast())), case .dictionary(let entries) = parent,
              entries.indices.contains(last) else { return false }
        let current = entries[last].key
        let key = rawKey(forDisplayed: text.trimmingCharacters(in: .whitespaces), current: current)
        guard key != current else { return true }
        guard !key.isEmpty else { return refuse("A key can't be empty.") }
        guard !entries.contains(where: { $0.key == key }) else { return refuse("The key “\(key)” is already in this dictionary.") }
        tree.setKey(key, at: path)
        return commit()
    }

    @discardableResult
    public func setValueText(_ text: String, at path: [Int]) -> Bool {
        guard let item = tree.item(at: path), !PlistTree.isContainer(item) else { return false }
        if PlistTree.editText(item) == text { return true }
        guard let v = PlistTree.parse(text, as: item.typeName) else {
            return refuse("“\(text)” is not a valid \(item.typeName == "Number" ? "number" : item.typeName.lowercased()) value.")
        }
        guard v != item else { return true }
        tree.setValue(v, at: path)
        return commit()
    }

    @discardableResult
    public func setType(_ type: String, at path: [Int]) -> Bool {
        guard let item = tree.item(at: path), item.typeName != type, PlistTree.types.contains(type) else { return false }
        tree.setType(type, at: path)
        if PlistTree.isContainer(tree.item(at: path) ?? item) { expanded.insert(path) }
        return commit()
    }

    @discardableResult
    public func addItem() -> [Int] {
        let sel = selection ?? []
        let asChild: Bool
        if let v = tree.item(at: sel), PlistTree.isContainer(v), sel.isEmpty || expanded.contains(sel) || PlistTree.children(of: v).isEmpty {
            asChild = true
        } else {
            asChild = false
        }
        let p = tree.insert(after: sel, asChild: asChild)
        if asChild { expanded.insert(sel) }
        shiftExpanded(inserting: p)
        selection = p
        commit()
        return p
    }

    @discardableResult
    public func removeSelected() -> Bool {
        guard let sel = selection, !sel.isEmpty, tree.item(at: sel) != nil else { return false }
        tree.remove(at: sel)
        shiftExpanded(removing: sel)
        let parent = Array(sel.dropLast())
        let count = tree.item(at: parent).map { PlistTree.children(of: $0).count } ?? 0
        selection = count == 0 ? parent : parent + [min(sel.last!, count - 1)]
        return commit()
    }

    @discardableResult
    public func moveSelected(by offset: Int) -> Bool {
        guard let sel = selection, let to = tree.move(at: sel, by: offset) else { return false }
        let fromOpen = expanded.filter { $0.starts(with: sel) }
        expanded.subtract(fromOpen)
        let between = sel.last! < to.last! ? (sel.last! + 1)...to.last! : to.last!...(sel.last! - 1)
        let step = sel.last! < to.last! ? -1 : 1
        let parent = Array(sel.dropLast())
        let shifted = expanded.filter { $0.count > parent.count && $0.starts(with: parent) && between.contains($0[parent.count]) }
        expanded.subtract(shifted)
        for p in shifted { var q = p; q[parent.count] += step; expanded.insert(q) }
        for p in fromOpen { expanded.insert(to + p.dropFirst(sel.count)) }
        selection = to
        return commit()
    }

    @discardableResult
    public func setTypeOfSelection(_ type: String) -> Bool {
        guard let sel = selection else { return false }
        return setType(type, at: sel)
    }

    public var selectedTypeName: String? { selection.flatMap { tree.item(at: $0)?.typeName } }

    public var canRemove: Bool { (selection.map { !$0.isEmpty }) ?? false }

    public func clearProblem() { problem = nil }

    public func reload() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        document = try PropertyListDocument(data: data)
        tree = PlistTree(root: document.root)
        if let s = selection, tree.item(at: s) == nil { selection = nil }
        problem = nil
    }

    private func shiftExpanded(inserting p: [Int]) {
        let parent = Array(p.dropLast()), at = p.last!
        expanded = Set(expanded.map { e in
            guard e.count > parent.count, e.starts(with: parent), e[parent.count] >= at else { return e }
            var q = e
            q[parent.count] += 1
            return q
        })
    }

    private func shiftExpanded(removing p: [Int]) {
        let parent = Array(p.dropLast()), at = p.last!
        expanded = Set(expanded.compactMap { e in
            guard e.count > parent.count, e.starts(with: parent) else { return e }
            if e[parent.count] == at { return nil }
            guard e[parent.count] > at else { return e }
            var q = e
            q[parent.count] -= 1
            return q
        })
    }

    @discardableResult
    private func refuse(_ why: String) -> Bool {
        problem = why
        return false
    }

    @discardableResult
    private func commit() -> Bool {
        document.root = tree.root
        do {
            try document.data().write(to: URL(fileURLWithPath: path), options: .atomic)
            problem = nil
            saveCount += 1
            return true
        } catch {
            problem = "Could not save “\((path as NSString).lastPathComponent)”: \(error.localizedDescription)"
            return false
        }
    }
}
