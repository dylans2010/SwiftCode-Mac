import Foundation
import Testing
@testable import YcodeIDECore
import YcodePreviews

@MainActor @Suite(.timeLimit(.minutes(30))) struct LivePreviewCanvasTests {
    let phone = CGSize(width: 402, height: 874)

    func tiles(_ n: Int) -> [PreviewLiveTile] {
        let regions = PreviewScreenLayout.regions((0..<n).map { PreviewTile(preview: $0, size: phone) }, screen: phone)
        return regions.enumerated().map { PreviewLiveTile(title: "P\($0.offset)", preview: $0.offset, region: $0.element) }
    }

    @Test func canvasLayoutKeepsTheDeviceArrangement() {
        let two = tiles(2)
        #expect(PreviewCanvasLayout.rows(two) == [[0, 1]])
        #expect(two[0].size == phone)
        let (frames, size) = PreviewCanvasLayout.frames(two, zoom: 0.5)
        #expect(frames[0].width == 201 && frames[0].height == 437 && frames[1].minX > frames[0].maxX)
        #expect(frames[0].minY == frames[1].minY && size.width == 16 + 201 + 16 + 201 + 16)
        let six = tiles(6)
        #expect(PreviewCanvasLayout.rows(six).map(\.count) == [3, 3])
        let z = PreviewCanvasLayout.fitZoom(two, area: CGSize(width: 600, height: 700))
        let (f2, s2) = PreviewCanvasLayout.frames(two, zoom: z)
        #expect(s2.width <= 600.5 && s2.height <= 700.5 && f2.count == 2)
        #expect(PreviewCanvasLayout.fitZoom(tiles(1), area: CGSize(width: 5000, height: 5000)) == 1)
    }

    @Test func tilePointsMapToDevicePointsAndPixels() {
        let t = tiles(2)[1]
        let p = PreviewCanvasLayout.devicePoint(CGPoint(x: 100.5, y: 218.5), in: CGSize(width: 201, height: 437), region: t.region)
        #expect(abs(p.x - (t.region.x + t.region.width / 2)) < 0.01 && abs(p.y - (t.region.y + t.region.height / 2)) < 0.01)
        #expect(PreviewCanvasLayout.devicePoint(CGPoint(x: -5, y: 1000), in: CGSize(width: 201, height: 437), region: t.region) == CGPoint(x: 201, y: t.region.y + 437))
        #expect(t.region.y == 218)
        let r = PreviewCanvasLayout.pixelRect(t.region, screen: phone, imageSize: CGSize(width: 1206, height: 2622))
        #expect(r == CGRect(x: 603, y: 654, width: 603, height: 1311))
    }

    @Test func previewDeviceCommands() {
        var s = RemoteSimulatorSettings(destination: "u@h", dataDirectory: "/d", runtimeRoot: "/rt/iOS-27.0/RuntimeRoot", simdPath: "/b/swiftcode-sim", deviceName: "dev")
        s.runtimeVersion = "27.0"
        let r = RemoteSimulator.all(s).first { $0.target?.deviceType.id == "iphone-18-pro" }!
        let pv = r.previewDevice
        #expect(pv.remoteDevicePath == "/d/devices/dev-iphone-18-pro-27.0-previews")
        #expect(pv.previewDirectory == "/d/devices/dev-iphone-18-pro-27.0-previews/data/tmp/swiftcode-previews")
        #expect(pv.displaySocketPath.hasPrefix("/d/display/pv-") && pv.displaySocketPath.hasSuffix(".sock") && pv.displaySocketPath.count <= 30)
        #expect(r.displaySocketPath == "/d/display/dev-iphone-18-pro-27.0.sock")
        let c = pv.previewCommand(platform: .iOS)
        #expect(c.contains("echo SWIFTCODE-REMOTE-PID $$; exec env SWIFTCODE_WARM_BOOT=1 '/b/swiftcode-sim' --device '/d/devices/dev-iphone-18-pro-27.0-previews'"))
        #expect(c.contains("'--device-type' 'iphone-18-pro'") && c.contains("--install-app '/d/apps/previews-iOS/SwiftCodePreviewHost.app' --launch 'dev.swiftcode.previewhost'"))
        #expect(c.contains("'--display-server' 'unix:\(pv.displaySocketPath)'"))
        var off = s
        off.warmBoot = false
        let offCommand = RemoteSimulator.all(off).first { $0.target?.deviceType.id == "iphone-18-pro" }.map { $0.previewDevice.previewCommand(platform: .iOS) } ?? ""
        #expect(offCommand.contains("SWIFTCODE_WARM_BOOT=1"))
        let plan = PreviewPlan(generation: 2, payload: "/tmp/swiftcode-previews/payload-2.dylib", regions: []).json()
        let d = pv.previewDeliverCommand(payloadName: "payload-2.dylib", plan: plan, keep: 40)
        #expect(d.contains("cat > 'payload-2.dylib.part' && mv 'payload-2.dylib.part' 'payload-2.dylib'"))
        #expect(d.contains("> plan.json.part && mv plan.json.part plan.json") && d.contains("tail -n +41"))
        #expect(d.range(of: "payload-2.dylib'")!.lowerBound < d.range(of: "plan.json.part")!.lowerBound)
        #expect(!pv.previewDeliverCommand(payloadName: nil, plan: plan, keep: 40).contains("cat >"))
        #expect(pv.previewReportCommand.hasSuffix("exec tail -n 0 -F '/d/devices/dev-iphone-18-pro-27.0-previews/data/tmp/swiftcode-previews/host.log'"))
    }
}
