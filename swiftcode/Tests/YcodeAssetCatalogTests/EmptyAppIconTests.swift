import Foundation
import Testing
@testable import YcodeAssetCatalog

@Suite struct EmptyAppIconTests {
    @Test func emptyAppIconSetWarnsAndCompiles() throws {
        let dir = try Fixture.tempDir("empty-icon")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cat = dir.appendingPathComponent("Assets.xcassets")
        try Fixture.json(["info": Fixture.info], to: cat)
        try Fixture.json(["images": [["idiom": "universal", "platform": "ios", "size": "1024x1024"]], "info": Fixture.info],
                         to: cat.appendingPathComponent("AppIcon.appiconset"))
        try Fixture.json(["colors": [["idiom": "universal"]], "info": Fixture.info], to: cat.appendingPathComponent("AccentColor.colorset"))
        let out = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let r = Fixture.compile([cat], platform: "iphonesimulator", out: out)
        #expect(r.succeeded, "\(r.diagnostics)")
        #expect(r.diagnostics.contains { $0.kind == .warning && $0.message.contains("has no images") })
    }
}
