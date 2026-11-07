import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import SwiftCodeAssistant

@Suite struct MuseOtherModelsProxyTests {
    private static let modelA = MuseOtherModelResolution(modelID: "gpt-4o", displayName: "OpenAI GPT-4o", provider: "OpenAI")
    private static let modelB = MuseOtherModelResolution(modelID: "claude-3-7-sonnet-20250219", displayName: "Claude 3.7 Sonnet", provider: "Anthropic")
    private static let fixtureExecutable = URL(fileURLWithPath: "/usr/bin/true")

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

        let sameURL = try await controller.enable(resolution: Self.modelA, executable: Self.fixtureExecutable, port: 0, streamChat: Self.stubStream())
        #expect(sameURL == firstURL)

        let secondURL = try await controller.enable(resolution: Self.modelB, executable: Self.fixtureExecutable, port: 0, streamChat: Self.stubStream())
        #expect(secondURL != firstURL)
        #expect(await controller.activeModel == Self.modelB)
        #expect(try await Self.catalogModelID(at: secondURL) == "claude-3-7-sonnet-20250219")

        do {
            _ = try await HTTP.send(URLRequest(url: firstURL.appendingPathComponent("/v1/models")), timeout: 5)
            Issue.record("old proxy URL still answers after a model-change restart")
        } catch {
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
