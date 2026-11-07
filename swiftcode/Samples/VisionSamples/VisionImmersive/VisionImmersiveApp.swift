import os
import RealityKit
import SwiftUI

let log = Logger(subsystem: "org.swiftcode.samples", category: "immersive")

@main
struct VisionImmersiveApp: App {
    @State private var style: ImmersionStyle = .mixed

    var body: some SwiftUI.Scene {
        WindowGroup {
            ControlsView()
        }
        ImmersiveSpace(id: "space") {
            ImmersiveView()
        }
        .immersionStyle(selection: $style, in: .mixed, .full)
    }
}

struct ControlsView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var state = "opening the immersive space"

    var body: some View {
        VStack(spacing: 16) {
            Text("SwiftCode sample: immersive space")
                .font(.largeTitle)
            Text(state)
        }
        .padding(40)
        .task {
            let result = await openImmersiveSpace(id: "space")
            switch result {
            case .opened: state = "opened"
            case .userCancelled: state = "cancelled"
            case .error: state = "error"
            @unknown default: state = "unknown"
            }
            log.notice("swiftcode-sample: openImmersiveSpace \(self.state)")
        }
    }
}

struct ImmersiveView: View {
    @State private var taps = 0

    var body: some View {
        RealityView { content in
            let sphere = ModelEntity(mesh: .generateSphere(radius: 0.2),
                                     materials: [SimpleMaterial(color: .systemPink, roughness: 0.3, isMetallic: false)])
            sphere.name = "sphere"
            sphere.position = [0.8, 1.3, -1.6]
            sphere.components.set(InputTargetComponent())
            sphere.generateCollisionShapes(recursive: false)
            content.add(sphere)
            for i in 0..<8 {
                let a = Float(i) / 8 * 2 * .pi
                let cube = ModelEntity(mesh: .generateBox(size: 0.1),
                                       materials: [SimpleMaterial(color: .systemTeal, isMetallic: false)])
                cube.position = [sin(a) * 0.5, 1.5 + cos(a) * 0.5, -1.5]
                content.add(cube)
            }
            log.notice("swiftcode-sample: immersive content made")
        } update: { content in
            if let sphere = content.entities.first(where: { $0.name == "sphere" }) as? ModelEntity {
                let colors: [UIColor] = [.systemPink, .systemGreen, .systemYellow, .systemPurple]
                sphere.model?.materials = [SimpleMaterial(color: colors[taps % colors.count], roughness: 0.3, isMetallic: false)]
            }
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { _ in
            taps += 1
            log.notice("swiftcode-sample: immersive tap \(self.taps)")
        })
        .onAppear { log.notice("swiftcode-sample: immersive space appeared") }
    }
}
