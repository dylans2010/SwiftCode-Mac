import Foundation

public struct SwiftPackageTemplate: ProjectTemplate {
    public let name = "Swift Package"
    public let description = "A template for a Swift package, suitable for libraries and tools."
    public let icon = "shippingbox"
    public let files: [TemplateFile] = [
        TemplateFile(path: "Package.swift", content: "// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: \"MyPackage\",\n    targets: [\n        .target(name: \"MyPackage\"),\n    ]\n)"),
        TemplateFile(path: "Sources/MyPackage/MyPackage.swift", content: "public struct MyPackage {\n    public init() {}\n}")
    ]
}
