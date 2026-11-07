import AppKit
import Foundation
import Testing
import SwiftCodeBuild
import SwiftCodeBuildServer
import SwiftCodeLanguage
@testable import SwiftCodeUI

@MainActor
@Suite(.serialized, .heavyIntegration, .timeLimit(.minutes(6))) struct BuildServerContextTests {
    static let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func liveIssuesFollowTheDestinationsSDK() async throws {
        let bsp = Self.packageRoot.appendingPathComponent(".build/debug/swiftcode-bsp").path
        let sdks = (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link")).map {
            $0 + "/Platforms/iPhoneSimulator.platform/Developer/SDKs"
        }
        guard SourceKitLSP.locate() != nil, FileManager.default.isExecutableFile(atPath: bsp),
              let sdks, !((try? FileManager.default.contentsOfDirectory(atPath: sdks)) ?? []).isEmpty else { return }
        setenv("SWIFTCODE_BSP", bsp, 1)
        defer { unsetenv("SWIFTCODE_BSP") }
        let dir = Self.packageRoot.appendingPathComponent(".build-ide/bsp-context")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let project = try SampleProject.write(.portable, in: dir)
        let pbx = project.appendingPathComponent("project.pbxproj")
        let text = try String(contentsOf: pbx, encoding: .utf8)
        try text.replacingOccurrences(of: "SDKROOT = macosx;",
                                      with: "SDKROOT = auto; SUPPORTED_PLATFORMS = \"macosx iphoneos iphonesimulator\"; IPHONEOS_DEPLOYMENT_TARGET = 18.0;")
            .write(to: pbx, atomically: true, encoding: .utf8)
        let kit = project.deletingLastPathComponent().appendingPathComponent("Kit/Greeter.swift")
        let source = try String(contentsOf: kit, encoding: .utf8)
            + "\n#if os(iOS)\nlet onlyOnIOS: Int = \"iOS\"\n#else\nlet onlyOnMac: Int = \"macOS\"\n#endif\n"
        let lines = source.components(separatedBy: "\n")
        let iosLine = try #require(lines.firstIndex { $0.contains("onlyOnIOS") }) + 1
        let macLine = try #require(lines.firstIndex { $0.contains("onlyOnMac") }) + 1

        let mac = Destination(name: "My Mac", specifier: "platform=macOS,arch=arm64", platform: "macOS", kind: .mac)
        let phone = Destination(name: "iPhone", specifier: "platform=iOS Simulator,arch=arm64", platform: "iOS Simulator", kind: .simulator)
        let session = WorkspaceSession(model: try WorkspaceModel(url: project))
        session.scheme = "App"
        session.destination = mac
        await session.startLanguageService()
        let first = try #require(session.language)
        #expect(session.languageServedContext?.destination == mac.specifier)
        first.open(kit, text: source)
        func errorLines() -> Set<Int> {
            Set(session.displayedIssues.filter { $0.severity == .error && $0.location?.file.hasSuffix("Kit/Greeter.swift") == true }
                .compactMap { $0.location?.line })
        }
        #expect(await waitUntil(120) { errorLines() == [macLine] }, "\(session.displayedIssues.map(\.message)) \(errorLines())")

        session.destination = phone
        await session.languageContextSettled()
        #expect(session.languageRestartCount == 1 && session.language !== first)
        let config = BuildServerLaunch.workspaceFolder(for: project).appendingPathComponent(".bsp/swiftcode.json")
        let argv = (try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])?["argv"] as? [String] ?? []
        #expect(argv.suffix(2) == ["--destination", phone.specifier])
        #expect(await waitUntil(120) { errorLines() == [iosLine] }, "\(session.displayedIssues.map(\.message)) \(errorLines())")
        await session.language?.stop()
    }
}
