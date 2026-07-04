import Foundation

public struct SafariExtensionTemplate: ProjectTemplate {
    public let name = "Safari Extension"
    public let description = "A template for a Safari web extension."
    public let icon = "safari"
    public let files: [TemplateFile] = [
        TemplateFile(path: "manifest.json", content: "{\n    \"manifest_version\": 3,\n    \"name\": \"My Extension\",\n    \"version\": \"1.0\"\n}"),
        TemplateFile(path: "background.js", content: "console.log(\"Background script running\");")
    ]
}
