import Foundation
import Testing
@testable import SwiftCodeAssistant

// Wave 17, Slice A: slash-command host effects + the execute-turn
// timeout. The applier tests are pure (no process); the timeout
// tests drive fixture `muse` scripts (a hanging one and the
// normal one from `MetaAssistBridgeTests`), never a live binary.

@Suite(.serialized) struct MetaSlashCommandEffectsTests {
    // MARK: - Effect applier

    @Test func effortSetsSettings() {
        let outcome = MetaSlashCommandEffectApplier.apply(
            .setReasoningEffort("low"), settings: AssistantSettings())
        #expect(outcome.settings.metaReasoningEffort == "low")
        #expect(outcome.message == "Meta reasoning effort set to 'low'.")
        #expect(outcome.clearsSession == false)
    }

    @Test func effortIsCaseInsensitiveAndCanonicalized() {
        let outcome = MetaSlashCommandEffectApplier.apply(
            .setReasoningEffort("HIGH"), settings: AssistantSettings())
        #expect(outcome.settings.metaReasoningEffort == "high")
        #expect(outcome.message == "Meta reasoning effort set to 'high'.")
    }

    @Test func unknownEffortChangesNothing() {
        var settings = AssistantSettings()
        settings.metaReasoningEffort = "medium"
        let outcome = MetaSlashCommandEffectApplier.apply(
            .setReasoningEffort("extreme"), settings: settings)
        #expect(outcome.settings.metaReasoningEffort == "medium")
        #expect(outcome.message.contains("Unknown reasoning effort 'extreme'"))
        #expect(outcome.message.contains("low, medium, high"))
    }

    @Test func knownModelIsRecordedWithoutCaveat() {
        let known: Set<String> = ["muse-wonder-1.0", "muse-spark-1.3"]
        let outcome = MetaSlashCommandEffectApplier.apply(
            .setModel("muse-spark-1.3"), settings: AssistantSettings(), knownModelIDs: known)
        #expect(outcome.settings.model(for: .metaAssist) == "muse-spark-1.3")
        #expect(outcome.message == "Meta Assist model switched to 'muse-spark-1.3'.")
    }

    @Test func unknownModelIsRecordedVerbatimWithCaveat() {
        // The router's rule: the selected id is never silently
        // replaced by another model — it is recorded as-is and
        // the user is told it is unknown to the catalog.
        let known: Set<String> = ["muse-wonder-1.0"]
        let outcome = MetaSlashCommandEffectApplier.apply(
            .setModel("muse-swift-2.0"), settings: AssistantSettings(), knownModelIDs: known)
        #expect(outcome.settings.model(for: .metaAssist) == "muse-swift-2.0")
        #expect(outcome.message.contains("not in the known Meta catalog"))
        #expect(outcome.message.contains("sends it as-is"))
    }

    @Test func clearSessionOutcome() {
        let outcome = MetaSlashCommandEffectApplier.apply(.clearSession, settings: AssistantSettings())
        #expect(outcome.clearsSession == true)
        #expect(outcome.message == "Cleared Assist session.")
        #expect(outcome.settings == AssistantSettings())
    }

    @Test func loginSurfacesTheHonestInstruction() {
        let outcome = MetaSlashCommandEffectApplier.apply(.startLogin, settings: AssistantSettings())
        #expect(outcome.message == MetaSlashCommandEffectApplier.loginInstruction)
        #expect(outcome.message.contains("run `muse` once in Terminal"))
        #expect(outcome.message.contains("never launches an interactive `muse login`"))
        #expect(outcome.settings == AssistantSettings())
        #expect(outcome.clearsSession == false)
    }

    // MARK: - Timeout value and classification

    @Test func defaultTurnTimeoutIs300() {
        #expect(MetaAssistTurnExecutor.defaultTurnTimeout == 300)
        #expect(AssistantSettings().metaTurnTimeoutSeconds == 300)
    }

    @Test func turnTimeoutClassifiesAsTimeout() {
        // The Wave 15 router must see this as a timeout (and,
        // with "Automatically Switch Models" off, never silently
        // substitute another model for it).
        let error = MuseCodeCLIError.turnTimeout(seconds: 300)
        #expect(error.localizedDescription.contains("timed out"))
        #expect(AssistModelRouter.classify(error: error) == .timeout)
    }

    // MARK: - Hanging host times out

    /// A fixture `muse` that answers `initialize` / `session/start` /
    /// `turn/start` and then never completes the turn — the host hangs.
    static let hangingMuseScript = """
        #!/usr/bin/env python3
        import sys, json
        def send(obj):
            sys.stdout.write(json.dumps(obj) + "\\n")
            sys.stdout.flush()
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except Exception:
                continue
            method = msg.get("method", "")
            rid = msg.get("id")
            if method == "initialize":
                send({"jsonrpc": "2.0", "id": rid, "result": {"capabilities": {}}})
            elif method == "session/start":
                send({"jsonrpc": "2.0", "id": rid, "result": {"session": {"sessionId": "sess-1"}}})
            elif method == "turn/start":
                send({"jsonrpc": "2.0", "id": rid, "result": {"turnId": "turn-1"}})
            else:
                send({"jsonrpc": "2.0", "id": rid, "result": {}})
        """

    static func installHangingMuse() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meta-hang-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("muse")
        try hangingMuseScript.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return dir
    }

    @Test func hangingTurnTimesOutAndStopsTheHost() async throws {
        guard MetaAssistBridgeTests.pythonAvailable() else { return }
        let dir = try Self.installHangingMuse()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bridge = MuseCodeMSPBridge()
        let executor = MetaAssistTurnExecutor(bridge: bridge)
        defer { Task { await bridge.stopHost() } }
        let started = Date()
        do {
            try await executor.executeTurn(
                prompt: "hello", modelID: "muse-wonder-1.0", workspaceRoot: dir.path,
                executable: dir.appendingPathComponent("muse"), hasCredentials: true,
                turnTimeoutSeconds: 1, onEvent: { _ in })
            Issue.record("expected the hanging turn to time out")
        } catch let error as MuseCodeCLIError {
            #expect(error == .turnTimeout(seconds: 1))
            #expect(error.localizedDescription.contains("timed out after 1 seconds"))
        }
        // The budget was ~1s, not the hang: the turn never hangs.
        #expect(Date().timeIntervalSince(started) < 30)
        // The host was stopped and the executor's session state
        // cleared, so the next turn starts fresh.
        #expect(await bridge.isRunning == false)
        #expect(await executor.activeSessionID == nil)
    }

    @Test func fastTurnStillCompletesWithTimeoutArmed() async throws {
        guard MetaAssistBridgeTests.pythonAvailable() else { return }
        let (dir, _, locator) = try MetaAssistBridgeTests.installFakeMuse()
        defer {
            MetaAssistBridgeTests.clearFakeMuseEnv()
            try? FileManager.default.removeItem(at: dir)
        }
        _ = locator
        let bridge = MuseCodeMSPBridge()
        let executor = MetaAssistTurnExecutor(bridge: bridge)
        defer { Task { await bridge.stopHost() } }
        final class EventBox: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var events: [ChatEvent] = []
            func append(_ e: ChatEvent) { lock.lock(); events.append(e); lock.unlock() }
        }
        let box = EventBox()
        try await executor.executeTurn(
            prompt: "hello", modelID: "muse-wonder-1.0", workspaceRoot: dir.path,
            executable: dir.appendingPathComponent("muse"), hasCredentials: true,
            turnTimeoutSeconds: 30, onEvent: { box.append($0) })
        #expect(box.events.contains(.text("Hello ")))
        #expect(box.events.contains(.text("world")))
        #expect(await executor.activeSessionID == "sess-1")
        await bridge.stopHost()
    }
}
