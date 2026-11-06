import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import YcodeAssistant

// NOTE: No Swift toolchain exists in this environment, so these tests
// have NOT been compiled or run — statically verified only. On Dylan's
// Mac: run with `swift test --filter MuseOtherModelsProxyTests`.
//
// Wave 17, Slice B: tests for the other-models proxy lifecycle
// (`MuseOtherModelsProxyController` + the `MuseLocalProxyServer`
// port fallback / model-change restart). No live network beyond
// loopback, no real `muse` binary (a fixture path stands in for
// the executable check, and the missing-binary case passes nil).

@Suite struct MuseOtherModelsProxyTests {
    private static let modelA = MuseOtherModelResolution(modelID: "gpt-4o", displayName: "OpenAI GPT-4o", provider: "OpenAI")
    private static let modelB = MuseOtherModelResolution(modelID: "claude-3-7-sonnet-20250219", displayName: "Claude 3.7 Sonnet", provider: "Anthropic")
    private static let fixtureExecutable = URL(fileURLWithPath: "/usr/bin/true")

    /// A streamChat that answers every request with two tokens.
    private static func stubStream() -> MuseLocalProxyServer.StreamChat {
        { _, _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield("Hello ")
                continuation.yield("world")
                continuation.finish()
            }
        }
    }

    private static func catalogModelID(at url: URL) async throws -> String? {
        let response = try await HTTP.send(URLRequest(url: url.appendingPathComponent("/v1/models")), timeout: 10)
        #expect(response.status == 200)
        let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        let data = json?["data"] as? [[String: Any]]
        return data?.first?["id"] as? String
    }

    @Test func modePredicate() {
        #expect(MuseOtherModelsProxyController.isOtherModelModeEnabled(otherModelsWithMetaSDK: false, swiftCodeCloudWithMetaSDK: false) == false)
        #expect(MuseOtherModelsProxyController.isOtherModelModeEnabled(otherModelsWithMetaSDK: true, swiftCodeCloudWithMetaSDK: false) == true)
        #expect(MuseOtherModelsProxyController.isOtherModelModeEnabled(otherModelsWithMetaSDK: false, swiftCodeCloudWithMetaSDK: true) == true)
        #expect(MuseOtherModelsProxyController.isOtherModelModeEnabled(otherModelsWithMetaSDK: true, swiftCodeCloudWithMetaSDK: true) == true)
    }

    @Test func controllerEnableDisableLifecycle() async throws {
        let controller = MuseOtherModelsProxyController()
        let url = try await controller.enable(resolution: Self.modelA, executable: Self.fixtureExecutable, port: 0, streamChat: Self.stubStream())
        #expect(await controller.isEnabled)
        #expect(await controller.proxyBaseURL == url.absoluteString)
        #expect(await controller.activeModel == Self.modelA)
        #expect(try await Self.catalogModelID(at: url) == "gpt-4o")

        await controller.disable()
        #expect(await controller.isEnabled == false)
        #expect(await controller.proxyBaseURL == nil)
        #expect(await controller.activeModel == nil)
    }

    @Test func controllerModelChangeRestarts() async throws {
        let controller = MuseOtherModelsProxyController()
        let firstURL = try await controller.enable(resolution: Self.modelA, executable: Self.fixtureExecutable, port: 0, streamChat: Self.stubStream())
        #expect(try await Self.catalogModelID(at: firstURL) == "gpt-4o")

        // Same model again: the running proxy is returned as-is.
        let sameURL = try await controller.enable(resolution: Self.modelA, executable: Self.fixtureExecutable, port: 0, streamChat: Self.stubStream())
        #expect(sameURL == firstURL)

        // A different model: restart, and the new proxy serves the
        // new model at a new URL.
        let secondURL = try await controller.enable(resolution: Self.modelB, executable: Self.fixtureExecutable, port: 0, streamChat: Self.stubStream())
        #expect(secondURL != firstURL)
        #expect(await controller.activeModel == Self.modelB)
        #expect(try await Self.catalogModelID(at: secondURL) == "claude-3-7-sonnet-20250219")

        // The old proxy is gone: its URL no longer answers.
        do {
            _ = try await HTTP.send(URLRequest(url: firstURL.appendingPathComponent("/v1/models")), timeout: 5)
            Issue.record("old proxy URL still answers after a model-change restart")
        } catch {
            // Expected: connection refused once the old server stopped.
        }
        await controller.disable()
    }

    @Test func controllerMuseMissingThrows() async throws {
        let controller = MuseOtherModelsProxyController()
        await #expect(throws: MuseOtherModelsProxyError.museNotFound) {
            try await controller.enable(resolution: Self.modelA, executable: nil, port: 0, streamChat: Self.stubStream())
        }
        #expect(await controller.isEnabled == false)
    }

    @Test func proxyPortTakenFallsBack() async throws {
        // Occupy the default port when it is free, so the proxy must
        // fall back to another loopback port. (If 19855 is already
        // taken in this environment the hold fails and the proxy
        // falls back anyway; the test still proves a running proxy.)
        let holder = try? LoopbackServer(port: MuseLocalProxyServer.defaultPort) { _ in .text("held") }
        defer { holder?.stop() }
        let proxy = MuseLocalProxyServer()
        defer { proxy.stop() }
        let url = try proxy.start(active: Self.modelA, port: MuseLocalProxyServer.defaultPort, streamChat: Self.stubStream())
        #expect(proxy.isRunning)
        if holder != nil {
            #expect(url.port != Int(MuseLocalProxyServer.defaultPort))
        }
        #expect(try await Self.catalogModelID(at: url) == "gpt-4o")
    }

    @Test func proxyStartSameModelIsIdempotent() async throws {
        let proxy = MuseLocalProxyServer()
        defer { proxy.stop() }
        let first = try proxy.start(active: Self.modelA, port: 0, streamChat: Self.stubStream())
        let second = try proxy.start(active: Self.modelA, port: 0, streamChat: Self.stubStream())
        #expect(first == second)
        #expect(proxy.activeModel == Self.modelA)
    }

    @Test func proxyStartDifferentModelRestarts() async throws {
        let proxy = MuseLocalProxyServer()
        defer { proxy.stop() }
        let first = try proxy.start(active: Self.modelA, port: 0, streamChat: Self.stubStream())
        let second = try proxy.start(active: Self.modelB, port: 0, streamChat: Self.stubStream())
        #expect(first != second)
        #expect(proxy.activeModel == Self.modelB)
        #expect(try await Self.catalogModelID(at: second) == "claude-3-7-sonnet-20250219")
    }
}
