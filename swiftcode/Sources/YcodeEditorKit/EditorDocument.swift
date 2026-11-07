import Foundation
import Observation
import YcodeSyntax

@Observable
public final class EditorDocument {
    public let path: String
    public let buffer: EditorBuffer
    @ObservationIgnored public private(set) var format: EditorFileFormat
    @ObservationIgnored public private(set) var stamp: EditorDiskStamp?
    public private(set) var readOnlyReason: String?
    public private(set) var diskChange: DiskChange?
    @ObservationIgnored public var viewState: AnyObject?

    public enum DiskChange: Equatable, Sendable {
        case modified, deleted
    }

    public enum SaveResult: Equatable, Sendable {
        case saved
        case conflict(DiskChange)
        case failed(String)
    }

    public var name: String { (path as NSString).lastPathComponent }
    public var isDirty: Bool { buffer.isDirty }

    public init(path: String, buffer: EditorBuffer, format: EditorFileFormat, stamp: EditorDiskStamp?, readOnlyReason: String? = nil) {
        self.path = path
        self.buffer = buffer
        self.format = format
        self.stamp = stamp
        self.readOnlyReason = readOnlyReason
        buffer.isReadOnly = readOnlyReason != nil
    }

    public static func open(path: String, typingOptions: TypingOptions = TypingOptions()) -> (document: EditorDocument?, message: String?) {
        let language = SyntaxLanguage(fileName: (path as NSString).lastPathComponent)
        switch EditorFile.load(path: path) {
        case .unavailable(let m):
            return (nil, m)
        case .text(let t, let f, let s):
            return (EditorDocument(path: path, buffer: EditorBuffer(text: t, language: language, typingOptions: typingOptions), format: f, stamp: s), nil)
        case .readOnly(let t, let reason, let s):
            return (EditorDocument(path: path, buffer: EditorBuffer(text: t, language: language, typingOptions: typingOptions),
                                   format: EditorFileFormat(), stamp: s, readOnlyReason: reason), nil)
        }
    }

    @discardableResult
    public func save(overwrite: Bool = false) -> SaveResult {
        guard readOnlyReason == nil else { return .failed(readOnlyReason ?? "Read-only") }
        if !overwrite {
            checkDisk()
            if let c = diskChange, c != .deleted || stamp != nil { return .conflict(c) }
        }
        do {
            stamp = try EditorFile.writeAtomically(EditorFile.encode(buffer.text, format: format), to: path)
            diskChange = nil
            buffer.breakUndoGroup()
            buffer.markSaved()
            return .saved
        } catch {
            return .failed("\(error)")
        }
    }

    @discardableResult
    public func checkDisk() -> DiskChange? {
        guard let stamp else {
            diskChange = nil
            return nil
        }
        if EditorFile.looksUnchanged(path: path, stamp: stamp) {
            if diskChange != nil { diskChange = nil }
            return nil
        }
        guard FileManager.default.fileExists(atPath: path) else {
            if diskChange != .deleted { diskChange = .deleted }
            return .deleted
        }
        guard let data = FileManager.default.contents(atPath: path) else { return diskChange }
        if EditorFile.hash(data) == stamp.contentHash {
            self.stamp = EditorFile.stamp(path: path, data: data)
            if diskChange != nil { diskChange = nil }
            return nil
        }
        if diskChange != .modified { diskChange = .modified }
        return .modified
    }

    @discardableResult
    public func reloadFromDisk() -> Bool {
        guard let data = FileManager.default.contents(atPath: path), let d = EditorFile.decode(data) else { return false }
        apply(text: d.text)
        format = d.format
        stamp = EditorFile.stamp(path: path, data: data)
        if readOnlyReason != nil { readOnlyReason = nil }
        buffer.isReadOnly = false
        if diskChange != nil { diskChange = nil }
        buffer.markSaved()
        return true
    }

    public func keepBufferOverDisk() {
        let data = FileManager.default.contents(atPath: path)
        stamp = data.map { EditorFile.stamp(path: path, data: $0) } ?? stamp
        if data == nil { stamp = nil }
        diskChange = nil
    }

    func apply(text: String) {
        let new = Array(text.utf16)
        let old = buffer.document.units
        var lo = 0
        while lo < old.count, lo < new.count, old[lo] == new[lo] { lo += 1 }
        var oldEnd = old.count, newEnd = new.count
        while oldEnd > lo, newEnd > lo, old[oldEnd - 1] == new[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }
        guard lo < oldEnd || lo < newEnd else { return }
        let caret = buffer.selection
        func map(_ o: Int) -> Int {
            if o <= lo { return o }
            if o >= oldEnd { return o + (newEnd - oldEnd) }
            return min(o, newEnd)
        }
        buffer.replace(NSRange(location: lo, length: oldEnd - lo), with: String(decoding: new[lo..<newEnd], as: UTF16.self),
                       selection: EditorSelection(anchor: map(caret.anchor), head: map(caret.head)))
    }

    public func restore(text: String) { apply(text: text) }
}
