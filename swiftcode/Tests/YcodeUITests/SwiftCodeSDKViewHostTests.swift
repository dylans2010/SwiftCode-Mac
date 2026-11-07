import XCTest
@testable import YcodeUI
import SwiftCodeSDK

@MainActor
final class SwiftCodeSDKViewHostTests: XCTestCase {

    @MainActor
    private final class FakeSurfaceActions: SDKViewSurfaceActions {
        var calls: [String] = []
        var errorToThrow: (any Error)?

        private func record(_ name: String) throws {
            calls.append(name)
            if let errorToThrow { throw errorToThrow }
        }

        func showDevices() async throws { try record("showDevices") }
        func showSimulators() async throws { try record("showSimulators") }
        func openInterfaceBuilder() async throws { try record("openInterfaceBuilder") }
        func showSymbolLibrary() throws { try record("showSymbolLibrary") }
        func showLivePreview() throws { try record("showLivePreview") }
        func showCodingAssistant() throws { try record("showCodingAssistant") }
        func showCodingDictionary() throws { try record("showCodingDictionary") }
        func showDatabaseExplorer() throws { try record("showDatabaseExplorer") }
        func showDocumentationBrowser() throws { try record("showDocumentationBrowser") }
        func showDeployConsole() async throws { try record("showDeployConsole") }
        func showCIDashboard() async throws { try record("showCIDashboard") }
        func showVirtualizationConsole() throws { try record("showVirtualizationConsole") }
        func showSandboxTerminal() async throws { try record("showSandboxTerminal") }
    }

    private func makeHost() -> (SwiftCodeSDKViewHost, FakeSurfaceActions) {
        let actions = FakeSurfaceActions()
        return (SwiftCodeSDKViewHost(actions: actions), actions)
    }

    private func assertThrowsServiceUnavailable(
        containing fragment: String? = nil,
        _ work: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await work()
            XCTFail("Expected .serviceUnavailable", file: file, line: line)
        } catch let error as SDKError {
            XCTAssertEqual(error.code, .serviceUnavailable, file: file, line: line)
            if let fragment {
                let text = (error.message + " " + (error.suggestion ?? "")).lowercased()
                XCTAssertTrue(text.contains(fragment.lowercased()), "Expected “\(fragment)” in “\(error.message) / \(error.suggestion ?? "")”", file: file, line: line)
            }
        } catch {
            XCTFail("Expected SDKError, got \(error)", file: file, line: line)
        }
    }

    func testWorkingWindowsRouteToSurfaces() async throws {
        let cases: [(viewID: String, surface: String)] = [
            ("deviceconnect.open", "showDevices"),
            ("simulator.view", "showSimulators"),
            ("uibuilder.open", "openInterfaceBuilder"),
            ("symbols.browse", "showSymbolLibrary"),
            ("preview.live", "showLivePreview"),
            (SDKAssistUIOpener.assistMainViewID, "showCodingAssistant"),
            ("dictionary.open", "showCodingDictionary"),
            ("db.ExploreView", "showDatabaseExplorer"),
            ("docs.search", "showDocumentationBrowser"),
            ("deployConsole.view", "showDeployConsole"),
            ("ci.VisualWF", "showCIDashboard"),
            ("virtualization.view", "showVirtualizationConsole"),
            ("sandbox.view", "showSandboxTerminal"),
        ]
        for (viewID, surface) in cases {
            let (host, actions) = makeHost()
            try await host.open(viewID: viewID)
            XCTAssertEqual(actions.calls, [surface], "View \(viewID) must open exactly its surface")
        }
    }

    func testUnavailableWindowsThrowWithReason() async {
        let cases: [(viewID: String, reason: String)] = []
        XCTAssertEqual(Set(cases.map(\.viewID)), Set(SwiftCodeSDKViewHost.unavailableReasons.keys))
        for (viewID, reason) in cases {
            let (host, actions) = makeHost()
            await assertThrowsServiceUnavailable(containing: reason) {
                try await host.open(viewID: viewID)
            }
            XCTAssertTrue(actions.calls.isEmpty, "Unavailable view \(viewID) must not touch any surface")
        }
    }

    func testAllTwelveViewIDsAreAccountedFor() {
        let working: Set<String> = [
            "deviceconnect.open", "simulator.view", "uibuilder.open",
            "symbols.browse", "preview.live",
            "dictionary.open", "db.ExploreView", "docs.search",
            "deployConsole.view", "ci.VisualWF",
            "virtualization.view", "sandbox.view",
        ]
        let unavailable = Set(SwiftCodeSDKViewHost.unavailableReasons.keys)
        XCTAssertTrue(working.isDisjoint(with: unavailable))
        XCTAssertEqual(
            working.union(unavailable),
            Set(SDKViewOpenerBuiltIns.builtInViewIDs),
            "Every built-in view ID must be either working or honestly unavailable"
        )
    }

    func testUnknownViewThrowsServiceUnavailable() async {
        let (host, actions) = makeHost()
        await assertThrowsServiceUnavailable {
            try await host.open(viewID: "not.a.view")
        }
        XCTAssertTrue(actions.calls.isEmpty)
    }

    func testSurfaceFailurePropagatesUnchanged() async {
        let (host, actions) = makeHost()
        let failure = SDKError(code: .projectNotOpen, message: "No project is open.")
        actions.errorToThrow = failure
        do {
            try await host.open(viewID: "uibuilder.open")
            XCTFail("Expected the surface error to propagate")
        } catch let error as SDKError {
            XCTAssertEqual(error.code, .projectNotOpen)
            XCTAssertEqual(error.message, "No project is open.")
        }
        XCTAssertEqual(actions.calls, ["openInterfaceBuilder"])
    }

    func testRegistryRoutesThroughInstalledHost() async throws {
        let (host, actions) = makeHost()
        SDKViewHostRegistry.shared.host = host
        defer { SDKViewHostRegistry.shared.host = nil }
        try await SDKViewHostRegistry.shared.open(viewID: "simulator.view")
        XCTAssertEqual(actions.calls, ["showSimulators"])
    }

    func testRegistryWithoutHostThrowsServiceUnavailable() async {
        SDKViewHostRegistry.shared.host = nil
        await assertThrowsServiceUnavailable {
            try await SDKViewHostRegistry.shared.open(viewID: "simulator.view")
        }
    }
}
