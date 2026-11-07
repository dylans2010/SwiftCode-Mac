import Foundation

@MainActor
public protocol SDKCodeFindableEditor: AnyObject {
    var findableText: String { get }

    func selectFindRange(_ range: Range<Int>)
}

@MainActor
public final class SDKCodeFindCoordinator: ObservableObject {
    public weak var editor: (any SDKCodeFindableEditor)? {
        didSet { recomputeMatches(selectFirst: !query.isEmpty) }
    }

    @Published public private(set) var query: String = ""

    @Published public var caseSensitive: Bool = false {
        didSet { recomputeMatches(selectFirst: true) }
    }

    @Published public private(set) var matches: [Range<Int>] = []

    @Published public private(set) var currentMatchIndex: Int?

    public init() {}

    public var hasMatches: Bool { currentMatchIndex != nil }

    public var matchSummaryText: String {
        if query.isEmpty { return "" }
        if matches.isEmpty { return "No matches" }
        if let index = currentMatchIndex {
            return "\(index + 1) of \(matches.count)"
        }
        return "\(matches.count) matches"
    }

    public func setQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        recomputeMatches(selectFirst: true)
    }

    public func editorTextDidChange() {
        let previousIndex = currentMatchIndex
        recomputeMatches(selectFirst: false)
        if let previousIndex, previousIndex < matches.count {
            currentMatchIndex = previousIndex
        }
    }

    public func findNext() {
        guard !matches.isEmpty else { return }
        let next = ((currentMatchIndex ?? -1) + 1) % matches.count
        selectMatch(at: next)
    }

    public func findPrevious() {
        guard !matches.isEmpty else { return }
        let current = currentMatchIndex ?? 0
        let previous = (current - 1 + matches.count) % matches.count
        selectMatch(at: previous)
    }

    private func selectMatch(at index: Int) {
        guard matches.indices.contains(index) else { return }
        currentMatchIndex = index
        editor?.selectFindRange(matches[index])
    }

    private func recomputeMatches(selectFirst: Bool) {
        let text = editor?.findableText ?? ""
        matches = Self.findAllMatches(of: query, caseSensitive: caseSensitive, in: text)
        if matches.isEmpty {
            currentMatchIndex = nil
        } else if selectFirst {
            selectMatch(at: 0)
        } else if let index = currentMatchIndex, index >= matches.count {
            currentMatchIndex = nil
        }
    }

    private static func findAllMatches(
        of query: String,
        caseSensitive: Bool,
        in text: String
    ) -> [Range<Int>] {
        guard !query.isEmpty else { return [] }
        let nsText = text as NSString
        var options: NSString.CompareOptions = [.literal]
        if !caseSensitive { options.insert(.caseInsensitive) }
        var ranges: [Range<Int>] = []
        var searchLocation = 0
        while searchLocation < nsText.length {
            let found = nsText.range(
                of: query,
                options: options,
                range: NSRange(location: searchLocation, length: nsText.length - searchLocation)
            )
            guard found.location != NSNotFound else { break }
            ranges.append(found.location..<(found.location + found.length))
            searchLocation = found.location + found.length
        }
        return ranges
    }
}
