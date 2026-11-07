import Foundation
import Testing
@testable import SwiftCodeIDECore
@testable import SwiftCodeUI

private func nsr(_ a: Int, _ l: Int = 0) -> NSRange { NSRange(location: a, length: l) }
private func offset(_ text: String, line: Int, column: Int = 0) -> Int { LineIndex(text).range(ofLine: line)!.location + column }

@Suite struct EditorTextCommandsTests {

    @Test @MainActor func minimapWidth() {
        #expect(MinimapView.width(forEditorWidth: 962) == 136)
        #expect(MinimapView.width(forEditorWidth: 480) == 73)
        #expect(MinimapView.width(forEditorWidth: 300) == 60)
    }
}
