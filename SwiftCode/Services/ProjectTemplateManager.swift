import Foundation

// MARK: - Project Template

struct ProjectTemplate: Identifiable {
    let id: String
    var name: String
    var description: String
    var icon: String
    var iconColor: String
    var files: [TemplateFile]
    var tags: [String]

    struct TemplateFile {
        var relativePath: String
        var content: (String) -> String // takes project name, returns content
    }
}

// MARK: - Project Template Manager

@MainActor
final class ProjectTemplateManager: ObservableObject {
    static let shared = ProjectTemplateManager()

    let templates: [ProjectTemplate] = ProjectTemplateManager.buildTemplates()

    private init() {}

    // MARK: - Apply Template

    func applyTemplate(_ template: ProjectTemplate, to project: Project) throws {
        for file in template.files {
            let content = file.content(project.name)
            let components = file.relativePath.components(separatedBy: "/")
            let fileName = components.last ?? file.relativePath
            let directory = components.dropLast().joined(separator: "/")
            let dirPath: String? = directory.isEmpty ? nil : directory

            if content == "__DIRECTORY__" {
                try ProjectManager.shared.createFolder(
                    named: fileName,
                    inDirectory: dirPath,
                    project: project
                )
            } else {
                try ProjectManager.shared.createFile(
                    named: fileName,
                    inDirectory: dirPath,
                    project: project,
                    initialContent: content
                )
            }
        }
    }

    // MARK: - Template Definitions

    private static func buildTemplates() -> [ProjectTemplate] {
        [
            swiftUIApp,
            swiftPackage,
            cliTool,
            gameApp,
            metalApp,
            imessageApp,
            watchApp,
            widgetKitExtension,
            visionOSApp,
            serverAPI,
            bluetoothUtility,
            staticWebsite,
            reactApp,
            htmlCssWebsite,
            javascriptApp,
            emptyProject,
            unitTestTarget
        ]
    }

    // MARK: - SwiftUI App

    private static var swiftUIApp: ProjectTemplate {
        ProjectTemplate(
            id: "swiftui_app",
            name: "SwiftUI App",
            description: "A full SwiftUI application with ContentView, App entry point, and basic navigation.",
            icon: "iphone",
            iconColor: "blue",
            files: [
                .init(relativePath: "Sources/AppEntry.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
import SwiftUI

@main
struct \(safeName)App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
"""
                },
                .init(relativePath: "Sources/Views/ContentView.swift") { name in
                    """
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "swift")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text("\(name)")
                    .font(.largeTitle.bold())
                Text("Built with SwiftCode")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("\(name)")
        }
    }
}

#Preview {
    ContentView()
}
"""
                },
                .init(relativePath: "Sources/Models/AppModel.swift") { _ in
                    """
import Foundation

@Observable
final class AppModel {
    var isLoading = false
    var errorMessage: String?
}
"""
                },
                .init(relativePath: "Package.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "\(safeName)",
    platforms: [.iOS(.v17)],
    targets: [
        .executableTarget(name: "\(safeName)", path: "Sources")
    ]
)
"""
                }
            ],
            tags: ["SwiftUI", "iOS", "App"]
        )
    }

    private static var swiftPackage: ProjectTemplate {
        ProjectTemplate(
            id: "swift_package",
            name: "Swift Package",
            description: "A Swift package with a library target, tests, and Package.swift.",
            icon: "shippingbox",
            iconColor: "orange",
            files: [
                .init(relativePath: "Package.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "\(safeName)",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "\(safeName)", targets: ["\(safeName)"]),
    ],
    targets: [
        .target(name: "\(safeName)", path: "Sources/\(safeName)"),
        .testTarget(name: "\(safeName)Tests",
                    dependencies: ["\(safeName)"],
                    path: "Tests/\(safeName)Tests"),
    ]
)
"""
                },
                .init(relativePath: "Sources/Library.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
// \(safeName) - Swift Package
import Foundation

public struct \(safeName) {
    public static let version = "1.0.0"

    public init() {}

    public func greet(name: String) -> String {
        // \\(name) generates literal Swift interpolation \(name) in the output file
        "Hello from \(safeName), \\(name)!"
    }
}
"""
                },
                .init(relativePath: "Tests/LibraryTests.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
import XCTest
@testable import \(safeName)

final class \(safeName)Tests: XCTestCase {
    func testGreet() {
        let lib = \(safeName)()
        XCTAssertEqual(lib.greet(name: "World"), "Hello from \(safeName), World!")
    }
}
"""
                }
            ],
            tags: ["SPM", "Library", "Framework"]
        )
    }

    private static var cliTool: ProjectTemplate {
        ProjectTemplate(
            id: "cli_tool",
            name: "CLI Tool",
            description: "A command-line Swift executable with argument parsing.",
            icon: "terminal",
            iconColor: "green",
            files: [
                .init(relativePath: "Sources/main.swift") { name in
                    """
import Foundation

// \(name) - Command Line Tool

let args = CommandLine.arguments
let programName = args.first ?? "\(name.lowercased())"

guard args.count > 1 else {
    print("Usage: \\(programName) <command> [options]")
    print("Commands: help, version, run")
    exit(0)
}

switch args[1].lowercased() {
case "help":
    print("\\(programName) - a Swift CLI tool")
    print("Commands: help, version, run")
case "version":
    print("\\(programName) v1.0.0")
case "run":
    print("Running \\(programName)...")
default:
    print("Unknown command: \\(args[1])")
    exit(1)
}
"""
                },
                .init(relativePath: "Package.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "\(safeName)",
    targets: [
        .executableTarget(name: "\(safeName)", path: "Sources")
    ]
)
"""
                }
            ],
            tags: ["CLI", "Terminal", "Tool"]
        )
    }

    private static var emptyProject: ProjectTemplate {
        ProjectTemplate(
            id: "empty",
            name: "Empty Project",
            description: "A blank project with just a README.",
            icon: "doc",
            iconColor: "gray",
            files: [
                .init(relativePath: "README.md") { name in
                    "# \(name)\n\nA new Swift project created with SwiftCode.\n"
                }
            ],
            tags: ["Empty", "Blank"]
        )
    }

    // MARK: - Game App (SpriteKit)

    private static var gameApp: ProjectTemplate {
        ProjectTemplate(
            id: "game_app",
            name: "Game (SpriteKit)",
            description: "A 2D game template using SpriteKit and SwiftUI's SpriteView.",
            icon: "gamecontroller.fill",
            iconColor: "purple",
            files: [
                .init(relativePath: "Sources/AppEntry.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
import SwiftUI

@main
struct \(safeName)App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
"""
                },
                .init(relativePath: "Sources/Views/ContentView.swift") { _ in
                    """
import SwiftUI
import SpriteKit

struct ContentView: View {
    var scene: SKScene {
        let scene = GameScene()
        scene.size = CGSize(width: 300, height: 400)
        scene.scaleMode = .resizeFill
        return scene
    }

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
    }
}
"""
                },
                .init(relativePath: "Sources/Scenes/GameScene.swift") { _ in
                    """
import SpriteKit

class GameScene: SKScene {
    override func didMove(to view: SKView) {
        let label = SKLabelNode(text: "Hello SpriteKit!")
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(label)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            let box = SKSpriteNode(color: .orange, size: CGSize(width: 50, height: 50))
            box.position = location
            addChild(box)
        }
    }
}
"""
                },
                .init(relativePath: "Package.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "\(safeName)",
    platforms: [.iOS(.v17)],
    targets: [
        .executableTarget(name: "\(safeName)", path: "Sources")
    ]
)
"""
                }
            ],
            tags: ["Game", "SpriteKit", "SwiftUI"]
        )
    }

    // MARK: - Metal App

    private static var metalApp: ProjectTemplate {
        ProjectTemplate(
            id: "metal_app",
            name: "Metal App",
            description: "A high-performance graphics template using Metal and MTKView.",
            icon: "sparkles",
            iconColor: "indigo",
            files: [
                .init(relativePath: "Sources/AppEntry.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
import SwiftUI

@main
struct \(safeName)App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
"""
                },
                .init(relativePath: "Sources/Views/ContentView.swift") { _ in
                    """
import SwiftUI
import MetalKit

struct ContentView: View {
    var body: some View {
        MetalView()
            .ignoresSafeArea()
    }
}

struct MetalView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)
        return mtkView
    }
    func updateUIView(_ uiView: MTKView, context: Context) {}
}
"""
                },
                .init(relativePath: "Sources/Shaders.metal") { _ in
                    """
#include <metal_stdlib>
using namespace metal;

fragment float4 fragmentShader() {
    return float4(1.0, 0.5, 0.2, 1.0);
}
"""
                },
                .init(relativePath: "Package.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "\(safeName)",
    platforms: [.iOS(.v17)],
    targets: [
        .executableTarget(name: "\(safeName)", path: "Sources")
    ]
)
"""
                }
            ],
            tags: ["Metal", "Graphics", "High Performance"]
        )
    }

    // MARK: - iMessage App

    private static var imessageApp: ProjectTemplate {
        ProjectTemplate(
            id: "imessage_app",
            name: "iMessage App",
            description: "A Messages extension template for building interactive apps in iMessage.",
            icon: "bubble.left.fill",
            iconColor: "green",
            files: [
                .init(relativePath: "Sources/MessagesViewController.swift") { _ in
                    """
import UIKit
import Messages

class MessagesViewController: MSMessagesAppViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let label = UILabel()
        label.text = "Hello iMessage!"
        label.textAlignment = .center
        label.frame = view.bounds
        view.addSubview(label)
    }
}
"""
                },
                .init(relativePath: "Package.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "\(safeName)",
    platforms: [.iOS(.v17)],
    targets: [
        .executableTarget(name: "\(safeName)", path: "Sources")
    ]
)
"""
                }
            ],
            tags: ["iMessage", "Extension", "Messages"]
        )
    }


    // MARK: - watchOS App

    private static var watchApp: ProjectTemplate {
        ProjectTemplate(
            id: "watch_app",
            name: "watchOS App",
            description: "A starter watchOS SwiftUI app with an app entry and simple interface.",
            icon: "applewatch",
            iconColor: "orange",
            files: [
                .init(relativePath: "Sources/WatchApp.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
import SwiftUI

@main
struct \(safeName)WatchApp: App {
    var body: some Scene {
        WindowGroup {
            Text("\(name) on watchOS")
        }
    }
}
"""
                }
            ],
            tags: ["watchOS", "SwiftUI", "App"]
        )
    }

    // MARK: - WidgetKit Extension

    private static var widgetKitExtension: ProjectTemplate {
        ProjectTemplate(
            id: "widgetkit_extension",
            name: "WidgetKit Extension",
            description: "A timeline widget starter with entry and view.",
            icon: "rectangle.grid.1x2.fill",
            iconColor: "purple",
            files: [
                .init(relativePath: "Sources/Widget.swift") { _ in
                    """
import WidgetKit
import SwiftUI

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct SampleWidgetEntryView: View {
    var entry: SimpleEntry

    var body: some View {
        Text(entry.date, style: .time)
    }
}
"""
                }
            ],
            tags: ["WidgetKit", "iOS", "Extension"]
        )
    }

    // MARK: - visionOS App

    private static var visionOSApp: ProjectTemplate {
        ProjectTemplate(
            id: "visionos_app",
            name: "visionOS App",
            description: "A basic visionOS SwiftUI app scene template.",
            icon: "visionpro",
            iconColor: "blue",
            files: [
                .init(relativePath: "Sources/VisionEntry.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
import SwiftUI

@main
struct \(safeName)VisionApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Welcome to \(name) on visionOS")
        }
    }
}
"""
                }
            ],
            tags: ["visionOS", "SwiftUI", "Spatial"]
        )
    }

    // MARK: - Server API

    private static var serverAPI: ProjectTemplate {
        ProjectTemplate(
            id: "server_api",
            name: "Server API",
            description: "A lightweight Swift HTTP server starter using async networking.",
            icon: "server.rack",
            iconColor: "green",
            files: [
                .init(relativePath: "Sources/main.swift") { _ in
                    """
import Foundation

@main
struct ServerMain {
    static func main() async {
        print("Starting Swift API server...")
        RunLoop.main.run()
    }
}
"""
                },
                .init(relativePath: "README.md") { name in
                    "# \(name) API\n\nRun this template as a foundation for a server-side Swift app."
                }
            ],
            tags: ["Server", "API", "Backend"]
        )
    }

    // MARK: - Bluetooth Utility

    private static var bluetoothUtility: ProjectTemplate {
        ProjectTemplate(
            id: "bluetooth_utility",
            name: "Bluetooth Utility",
            description: "CoreBluetooth starter for scanning nearby peripherals.",
            icon: "dot.radiowaves.left.and.right",
            iconColor: "cyan",
            files: [
                .init(relativePath: "Sources/BluetoothManager.swift") { _ in
                    """
import CoreBluetooth

final class BluetoothManager: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil)
        }
    }
}
"""
                }
            ],
            tags: ["CoreBluetooth", "Utility", "iOS"]
        )
    }

    // MARK: - Web Templates

    private static var staticWebsite: ProjectTemplate {
        ProjectTemplate(
            id: "static_website",
            name: "Static Website",
            description: "A simple static website with HTML, CSS, and JS.",
            icon: "globe",
            iconColor: "blue",
            files: [
                .init(relativePath: "index.html") { name in
                    "<!DOCTYPE html>\n<html>\n<head>\n    <title>\(name)</title>\n    <link rel='stylesheet' href='style.css'>\n</head>\n<body>\n    <h1>Welcome to \(name)</h1>\n    <script src='script.js'></script>\n</body>\n</html>"
                },
                .init(relativePath: "style.css") { _ in
                    "body {\n    font-family: sans-serif;\n    display: flex;\n    justify-content: center;\n    align-items: center;\n    height: 100vh;\n    background: #f0f0f0;\n}"
                },
                .init(relativePath: "script.js") { _ in
                    "console.log('Website loaded');"
                }
            ],
            tags: ["Web", "HTML", "CSS", "JS"]
        )
    }

    private static var reactApp: ProjectTemplate {
        ProjectTemplate(
            id: "react_app",
            name: "React App",
            description: "A basic React application template.",
            icon: "atom",
            iconColor: "cyan",
            files: [
                .init(relativePath: "package.json") { name in
                    "{\n  \"name\": \"\(name.lowercased().replacingOccurrences(of: " ", with: "-"))\",\n  \"version\": \"1.0.0\",\n  \"dependencies\": {\n    \"react\": \"^18.2.0\",\n    \"react-dom\": \"^18.2.0\"\n  }\n}"
                },
                .init(relativePath: "src/App.js") { _ in
                    "import React from 'react';\n\nfunction App() {\n  return (\n    <div className=\"App\">\n      <h1>Hello React</h1>\n    </div>\n  );\n}\n\nexport default App;"
                },
                .init(relativePath: "public/index.html") { name in
                    "<!DOCTYPE html>\n<html lang=\"en\">\n  <head>\n    <title>\(name)</title>\n  </head>\n  <body>\n    <div id=\"root\"></div>\n  </body>\n</html>"
                }
            ],
            tags: ["Web", "React", "JS"]
        )
    }

    private static var htmlCssWebsite: ProjectTemplate {
        ProjectTemplate(
            id: "html_css_website",
            name: "HTML/CSS Website",
            description: "A clean HTML and CSS starter.",
            icon: "doc.plaintext",
            iconColor: "orange",
            files: [
                .init(relativePath: "index.html") { name in
                    "<!DOCTYPE html>\n<html>\n<head>\n    <title>\(name)</title>\n    <style>\n        body { margin: 0; padding: 20px; }\n    </style>\n</head>\n<body>\n    <h1>\(name)</h1>\n</body>\n</html>"
                }
            ],
            tags: ["Web", "HTML", "CSS"]
        )
    }

    private static var javascriptApp: ProjectTemplate {
        ProjectTemplate(
            id: "javascript_app",
            name: "JavaScript App",
            description: "A vanilla JavaScript application starter.",
            icon: "js",
            iconColor: "yellow",
            files: [
                .init(relativePath: "index.html") { name in
                    "<!DOCTYPE html>\n<html>\n<body>\n    <h1 id='title'>\(name)</h1>\n    <script src='app.js'></script>\n</body>\n</html>"
                },
                .init(relativePath: "app.js") { _ in
                    "document.getElementById('title').style.color = 'blue';"
                }
            ],
            tags: ["Web", "JS"]
        )
    }

    // MARK: - Unit Test Target

    private static var unitTestTarget: ProjectTemplate {
        ProjectTemplate(
            id: "unit_tests",
            name: "Unit Tests",
            description: "XCTest-based unit test suite for an existing project.",
            icon: "checkmark.shield",
            iconColor: "cyan",
            files: [
                .init(relativePath: "Tests/AppTests.swift") { name in
                    let safeName = name.replacingOccurrences(of: " ", with: "")
                    return """
import XCTest
@testable import \(safeName)

final class \(safeName)Tests: XCTestCase {

    override func setUpWithError() throws {
        // Setup before each test
    }

    override func tearDownWithError() throws {
        // Cleanup after each test
    }

    func testExample() throws {
        XCTAssertTrue(true, "This is a placeholder test")
    }

    func testPerformanceExample() throws {
        measure {
            // performance test code
        }
    }
}
"""
                }
            ],
            tags: ["Testing", "XCTest"]
        )
    }
}
