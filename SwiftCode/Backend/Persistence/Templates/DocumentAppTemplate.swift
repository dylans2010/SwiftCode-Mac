import Foundation

public struct DocumentAppTemplate: ProjectTemplate {
    public let name = "Document App"
    public let description = "A document-based app for macOS."
    public let icon = "doc.text"
    public let files: [TemplateFile] = [
        TemplateFile(path: "Document.swift", content: "import SwiftUI\nimport UniformTypeIdentifiers\n\nstruct MyDocument: FileDocument {\n    var text: String\n    init(text: String = \"\") { self.text = text }\n    static var readableContentTypes: [UTType] { [.plainText] }\n    init(configuration: ReadConfiguration) throws {\n        guard let data = configuration.file.contents,\n              let string = String(data: data, encoding: .utf8)\n        else { throw CocoaError(.fileReadCorruptFile) }\n        text = string\n    }\n    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {\n        Data(text.utf8).makeFileWrapper()\n    }\n}"),
        TemplateFile(path: "ContentView.swift", content: "import SwiftUI\n\nstruct ContentView: View {\n    @Binding var document: MyDocument\n    var body: some View {\n        TextEditor(text: $document.text)\n    }\n}"),
        TemplateFile(path: "App.swift", content: "import SwiftUI\n\n@main\nstruct DocumentApp: App {\n    var body: some Scene {\n        DocumentGroup(newDocument: MyDocument()) { file in\n            ContentView(document: file.$document)\n        }\n    }\n}")
    ]
}
