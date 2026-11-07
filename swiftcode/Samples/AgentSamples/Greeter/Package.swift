// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Greeter",
    products: [.executable(name: "greet", targets: ["greet"])],
    targets: [
        .target(name: "Greeter"),
        .executableTarget(name: "greet", dependencies: ["Greeter"]),
        .testTarget(name: "GreeterTests", dependencies: ["Greeter"]),
    ]
)
