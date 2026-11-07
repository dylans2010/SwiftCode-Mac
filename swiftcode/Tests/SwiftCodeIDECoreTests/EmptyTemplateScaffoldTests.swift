import Testing
import SwiftCodeIDECore

@Suite struct EmptyTemplateScaffoldTests {
    @Test func emptyTemplateStartsBlank() {
        let template = EmptyTemplate()
        #expect(template.name == "Empty")
        #expect(template.files.isEmpty)
        #expect(!template.description.isEmpty)
        #expect(template.icon == "square.dashed")
    }
}
