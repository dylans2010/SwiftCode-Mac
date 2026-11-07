import Foundation
import Testing
@testable import SwiftCodeIDECore
import SwiftCodePreviews

@MainActor
@Suite(.timeLimit(.minutes(30))) struct PreviewCanvasChromeTests {
    @Test func tabTitlesFromNameOrViewType() {
        let p = PreviewDiscovery.previews(in: "#Preview(\"Named\") { Text(\"a\") }\n#Preview {\n  @Previewable @State var x = 1\n  Badge(text: \"b\")\n}\n#Preview { 42 }")
        #expect(p.map(\.tabTitle) == ["Named", "Badge", "Preview 2"])
        #expect(p.map(\.isNamed) == [true, false, false])
    }
}
