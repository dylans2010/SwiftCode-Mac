import Foundation

public struct SystemExtensionTemplate: ProjectTemplate {
    public let name = "System Extension"
    public let description = "A template for creating a macOS system extension (e.g., Network Extension)."
    public let icon = "puzzlepiece"
    public let files: [TemplateFile] = [
        TemplateFile(path: "main.swift", content: "import Foundation\nimport SystemExtensions\n\nclass ExtensionDelegate: NSObject, OSSystemExtensionRequestDelegate {\n    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {}\n    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {}\n}")
    ]
}
