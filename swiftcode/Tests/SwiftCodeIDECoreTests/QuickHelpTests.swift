import Foundation
import Testing
import SwiftCodeDebug
import SwiftCodeLanguage
@testable import SwiftCodeIDECore

@Suite struct QuickHelpFormatterTests {
    @Test func markdownToPlain() {
        let md = "```swift\nstruct Greeter\n```\n\n---\n\n\n A `greeting` printer.\n"
        #expect(QuickHelpFormatter.plain(md) == "struct Greeter\n\n A greeting printer.")
    }
}
