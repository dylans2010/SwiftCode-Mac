// SwiftUIViewLibraryTemplate.swift
//
// Ported from Legacy `SwiftCode/Backend/Persistence/Templates/SwiftUIViewLibraryTemplate.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: distinct 'SwiftUI View Library' template producing MyComponent.swift (a SwiftUI View with Text("Custom Component"))
// Ambiguous type reference(s) defined in several modules, import left out: TemplateFile.
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftCodeIDECore
import Foundation

public struct SwiftUIViewLibraryTemplate: ProjectScaffoldTemplate {
    public let name = "SwiftUI View Library"
    public let description = "A library of reusable SwiftUI components."
    public let icon = "macwindow.on.rectangle"
    public let files: [TemplateFile] = [
        TemplateFile(path: "MyComponent.swift", content: "import SwiftUI\n\npublic struct MyComponent: View {\n    public init() {}\n    public var body: some View {\n        Text(\"Custom Component\")\n    }\n}")
    ]
}
