import Foundation
import YcodePlist

extension PlistTree {
    @discardableResult
    public mutating func move(at path: [Int], by offset: Int) -> [Int]? {
        guard let last = path.last, offset != 0 else { return nil }
        let parentPath = Array(path.dropLast())
        guard let parent = item(at: parentPath) else { return nil }
        let count = Self.children(of: parent).count
        guard (0..<count).contains(last) else { return nil }
        let target = min(max(last + offset, 0), count - 1)
        guard target != last else { return nil }
        let moved: PropertyListItem
        switch parent {
        case .dictionary(var d):
            let e = d.remove(at: last)
            d.insert(e, at: target)
            moved = .dictionary(d)
        case .array(var a):
            let e = a.remove(at: last)
            a.insert(e, at: target)
            moved = .array(a)
        default: return nil
        }
        setValue(moved, at: parentPath)
        return parentPath + [target]
    }

    public enum SortColumn: String, Sendable, CaseIterable { case key = "Key", type = "Type", value = "Value" }

    public static func displayOrder(of container: PropertyListItem, by column: SortColumn?, ascending: Bool = true) -> [Int] {
        let kids = children(of: container)
        let indices = Array(kids.indices)
        guard let column else { return indices }
        if column == .key, case .array = container { return ascending ? indices : indices.reversed() }
        func text(_ i: Int) -> String {
            switch column {
            case .key: kids[i].key
            case .type: kids[i].value.typeName
            case .value: kids[i].value.summary
            }
        }
        let sorted = indices.sorted { a, b in
            let order = text(a).localizedStandardCompare(text(b))
            if order == .orderedSame { return a < b }
            return (order == .orderedAscending) == ascending
        }
        return sorted
    }
}
