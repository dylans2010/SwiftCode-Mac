import Foundation
import Testing
import YcodeSyntax
@testable import YcodeEditorKit

@Suite struct CellCharacterWidthTests {
    @Test func blocksAdvanceOneCellWhateverTheirFace() {
        let layout = EditorLineLayout(tabWidth: 4, advance: 8) { $0 == "\u{2588}" ? 6.89 : 7.2 }
        #expect(layout.width(of: "\u{2588}") == 8)
        #expect(layout.width(of: "\u{2500}") == 8 && layout.width(of: "\u{25CF}") == 8 && layout.width(of: "\u{2800}") == 8)
        #expect(layout.width(of: "a") == 8)
        #expect(layout.width(of: "é") == 7.2)
        let b = EditorBuffer(text: "// " + String(repeating: "\u{2588}", count: 110), language: .swift)
        let end = layout.x(ofOffset: 113, line: 0, in: b)
        #expect(abs(end - 904) < 0.001, "\(end)")
        #expect(EditorCellCharacters.contains("ab\u{2588}") && !EditorCellCharacters.contains("abc"))
    }
}
