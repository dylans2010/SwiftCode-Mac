## 11. ADVANCED SWIFT & MACOS TECHNICAL CORPUS

This asset provides production-grade architectural patterns, strict Swift 6 concurrency models, and AppKit/SwiftUI bridging references.

---

## 10.1 Modern Concurrency Architecture
Strict Swift 6 concurrency enforces Sendable checking, complete data isolation across task boundaries, and actor-isolated mutation state.

```swift
import Foundation

/// Thread-safe state container demonstrating strict Swift 6 actor boundary enforcement.
public actor ProjectMetricsCache {
    private var cachedSizes: [URL: Int64] = [:]
    private var inFlightAudits: [URL: Task<Int64, Error>] = [:]

    public init() {}

    public func getOrComputeSize(for directory: URL) async throws -> Int64 {
        if let size = cachedSizes[directory] {
            return size
        }

        if let existingTask = inFlightAudits[directory] {
            return try await existingTask.value
        }

        let auditTask = Task.detached(priority: .userInitiated) { () -> Int64 in
            let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return 0
            }

            var total: Int64 = 0
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: resourceKeys)
                if values.isDirectory != true {
                    total += Int64(values.fileSize ?? 0)
                }
            }
            return total
        }

        inFlightAudits[directory] = auditTask

        do {
            let result = try await auditTask.value
            cachedSizes[directory] = result
            inFlightAudits.removeValue(forKey: directory)
            return result
        } catch {
            inFlightAudits.removeValue(forKey: directory)
            throw error
        }
    }

    public func invalidate(for directory: URL) {
        cachedSizes.removeValue(forKey: directory)
    }
}
```

---

## 10.2 MainActor UI Integration & AppKit/SwiftUI Bridging
Interfacing native AppKit components (`NSTextView`, `NSScrollView`) with SwiftUI requires `@MainActor` isolation and Coordinator pattern bridging to prevent main-thread deadlocks or race conditions.

```swift
import SwiftUI
import AppKit

/// Native AppKit NSTextView wrapped safely inside SwiftUI with MainActor isolation.
@MainActor
public struct NativeConsoleEditor: NSViewRepresentable {
    @Binding public var text: String
    public var isEditable: Bool

    public init(text: Binding<String>, isEditable: Bool = true) {
        self._text = text
        self.isEditable = isEditable
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.autoresizingMask = [.width, .height]

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        private var parent: NativeConsoleEditor

        init(_ parent: NativeConsoleEditor) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
        }
    }
}
```
