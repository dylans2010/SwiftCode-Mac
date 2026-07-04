import Foundation

public struct GameMetalTemplate: ProjectTemplate {
    public let name = "Metal Game"
    public let description = "A high-performance game template using the Metal framework."
    public let icon = "cpu"
    public let files: [TemplateFile] = [
        TemplateFile(path: "Renderer.swift", content: "import Metal\nimport MetalKit\n\nclass Renderer: NSObject, MTKViewDelegate {\n    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}\n    func draw(in view: MTKView) {\n        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }\n        // Drawing logic here\n    }\n}"),
        TemplateFile(path: "GameViewController.swift", content: "import AppKit\nimport MetalKit\n\nclass GameViewController: NSViewController {\n    var renderer: Renderer!\n    override func viewDidLoad() {\n        super.viewDidLoad()\n        let mtkView = view as! MTKView\n        mtkView.device = MTLCreateSystemDefaultDevice()\n        renderer = Renderer()\n        mtkView.delegate = renderer\n    }\n}")
    ]
}
