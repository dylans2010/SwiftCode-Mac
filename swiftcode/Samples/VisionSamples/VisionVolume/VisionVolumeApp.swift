import os
import RealityKit
import SwiftUI

let log = Logger(subsystem: "org.swiftcode.samples", category: "volume")

@main
struct VisionVolumeApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup {
            VolumeView()
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.6, height: 0.6, depth: 0.6, in: .meters)
    }
}

struct VolumeView: View {
    @State private var turns = 0

    var body: some View {
        RealityView { content in
            let box = ModelEntity(mesh: .generateBox(size: 0.25, cornerRadius: 0.03),
                                  materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)])
            box.name = "box"
            box.components.set(InputTargetComponent())
            box.generateCollisionShapes(recursive: false)
            let sphere = ModelEntity(mesh: .generateSphere(radius: 0.09),
                                     materials: [SimpleMaterial(color: .systemOrange, roughness: 0.2, isMetallic: true)])
            sphere.position = [0.18, 0.15, 0.05]
            content.add(box)
            content.add(sphere)
            log.notice("swiftcode-sample: volume content made")
        } update: { content in
            if let box = content.entities.first(where: { $0.name == "box" }) {
                box.transform.rotation = simd_quatf(angle: Float(turns) * .pi / 8, axis: [0, 1, 0])
            }
        }
        .gesture(TapGesture().targetedToAnyEntity().onEnded { _ in
            turns += 1
            log.notice("swiftcode-sample: volume tap \(self.turns)")
        })
        .onAppear { log.notice("swiftcode-sample: volume appeared") }
    }
}
