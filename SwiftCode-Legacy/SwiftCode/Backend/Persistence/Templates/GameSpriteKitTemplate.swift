import Foundation

public struct GameSpriteKitTemplate: ProjectScaffoldTemplate {
    public let name = "SpriteKit Game"
    public let description = "A 2D game template using the SpriteKit framework."
    public let icon = "gamecontroller"
    public let files: [TemplateFile] = [
        TemplateFile(path: "GameScene.swift", content: "import SpriteKit\n\nclass GameScene: SKScene {\n    override func didMove(to view: SKView) {\n        let label = SKLabelNode(text: \"Hello SpriteKit!\")\n        addChild(label)\n    }\n}"),
        TemplateFile(path: "AppDelegate.swift", content: "import AppKit\nimport SpriteKit\n\n@main\nclass AppDelegate: NSObject, NSApplicationDelegate {\n    func applicationDidFinishLaunching(_ notification: Notification) {\n        // Setup window and SKView\n    }\n}")
    ]
}
