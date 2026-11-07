// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Codegen",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Codegen", targets: ["Codegen"]),
        .plugin(name: "CodegenPlugin", targets: ["CodegenPlugin"]),
    ],
    targets: [
        .executableTarget(name: "codegen-tool"),
        .plugin(name: "CodegenPlugin", capability: .buildTool(), dependencies: ["codegen-tool"]),
        .target(name: "Codegen", plugins: ["CodegenPlugin"]),
    ]
)
