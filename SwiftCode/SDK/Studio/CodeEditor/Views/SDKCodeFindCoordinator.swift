import Foundation

// MARK: - SDKCodeFindableEditor
//
// The hook an editor view registers so the find bar can move its
// selection. Offsets are UTF-16 code-unit offsets into `findableText` —
// the same convention as `SDKToken.range` and `NSRange` — so an
// AppKit-backed editor can convert directly with `NSRange(location:length:)`
// and a SwiftUI `TextEditor` can map through its string's UTF-16 view.
//
// The reference is held WEAKLY by `SDKCodeFindCoordinator`: the editor
// view owns the coordinator (or a shared parent owns both), never the
// other way around.

@MainActor
public protocol SDKCodeFindableEditor: AnyObject {
    /// The full current text of the editor buffer.
    var findableText: String { get }

    /// Selects `range` (UTF-16 offsets into `findableText`) and scrolls it
    /// into view. Implementations MUST ignore out-of-bounds ranges rather
    /// than trapping: the buffer may have changed between match
    /// computation and selection.
    func selectFindRange(_ range: Range<Int>)
}

// MARK: - SDKCodeFindCoordinator
//
// Small, real find engine shared by the find bar and the editor view.
//
// WIRING (the editor view is a sibling task; this is the contract):
//   1. A parent view creates ONE coordinator (e.g. `@StateObject`) and
//      passes it to both `SDKCodeFindBarView` and the editor view.
//   2. The editor view sets `coordinator.editor = self` on appear (and
//      `nil` on disappear), and calls `editorTextDidChange()` whenever
//      its buffer text changes.
//   3. The find bar binds its field to `SDKCodeEditorState.findQuery` and
//      forwards changes via `setQuery(_)`; `caseSensitive` is bound
//      directly to the coordinator.
//   4. Next/previous buttons call `findNext()` / `findPrevious()`, which
//      move the real selection through the registered editor hook.
//
// Matching is literal substring search over the editor's CURRENT text
// (not a stale copy): every recompute re-reads `editor?.findableText`.
// Case-insensitivity is folded in via `.caseInsensitive`; there is no
// regex and no second schema to drift out of sync.

@MainActor
public final class SDKCodeFindCoordinator: ObservableObject {
    /// The registered editor, held weakly. `nil` when no editor is
    /// showing (or the sibling editor view has not registered yet); all
    /// find actions become no-ops that still keep `matches` honest.
    public weak var editor: (any SDKCodeFindableEditor)? {
        didSet { recomputeMatches(selectFirst: !query.isEmpty) }
    }

    /// The current query. The find bar keeps this in sync with
    /// `SDKCodeEditorState.findQuery` via `setQuery(_)`; it is published
    /// here (rather than read from state) so the coordinator also works
    /// standalone in previews and tests.
    @Published public private(set) var query: String = ""

    /// Case-sensitivity of matching. Bound directly to the find bar's
    /// toggle; toggling recomputes matches immediately.
    @Published public var caseSensitive: Bool = false {
        didSet { recomputeMatches(selectFirst: true) }
    }

    /// All current matches as UTF-16 offset ranges into the editor text
    /// at compute time, in document order.
    @Published public private(set) var matches: [Range<Int>] = []

    /// Index into `matches` of the currently selected match, or `nil`
    /// when there is no selection (empty query or no matches).
    @Published public private(set) var currentMatchIndex: Int?

    public init() {}

    /// `true` when at least one match exists.
    public var hasMatches: Bool { currentMatchIndex != nil }

    /// "2 of 9", "No matches", or "" when the query is empty — the find
    /// bar's match-count display.
    public var matchSummaryText: String {
        if query.isEmpty { return "" }
        if matches.isEmpty { return "No matches" }
        if let index = currentMatchIndex {
            return "\(index + 1) of \(matches.count)"
        }
        return "\(matches.count) matches"
    }

    // MARK: - Inputs from the find bar / editor view

    /// Sets the query (called by the find bar from
    /// `SDKCodeEditorState.findQuery`). Recomputes and jumps the editor
    /// selection to the first match, like Xcode's live find.
    public func setQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        recomputeMatches(selectFirst: true)
    }

    /// Called by the editor view after its buffer text changes. Recomputes
    /// matches WITHOUT stealing the selection: while the user is typing,
    /// jumping the caret to a match would fight them. The current index
    /// is preserved when it is still in bounds.
    public func editorTextDidChange() {
        let previousIndex = currentMatchIndex
        recomputeMatches(selectFirst: false)
        if let previousIndex, previousIndex < matches.count {
            currentMatchIndex = previousIndex
        }
    }

    // MARK: - Navigation

    /// Selects the next match, wrapping around at the end of the buffer.
    /// No-op when there are no matches.
    public func findNext() {
        guard !matches.isEmpty else { return }
        let next = ((currentMatchIndex ?? -1) + 1) % matches.count
        selectMatch(at: next)
    }

    /// Selects the previous match, wrapping around at the start of the buffer.
    /// No-op when there are no matches.
    public func findPrevious() {
        guard !matches.isEmpty else { return }
        let current = currentMatchIndex ?? 0
        let previous = (current - 1 + matches.count) % matches.count
        selectMatch(at: previous)
    }

    // MARK: - Private

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

    /// Literal substring search returning UTF-16 offset ranges in document
    /// order. Done on `NSString` so ranges come out natively in UTF-16
    /// offsets with no index conversion. Total: any query/text returns a
    /// valid (possibly empty) array.
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
            // `query` is non-empty so `found.length >= 1`: always advances.
            searchLocation = found.location + found.length
        }
        return ranges
    }
}
