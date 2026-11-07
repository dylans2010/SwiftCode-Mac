import AppKit
import Foundation
import Testing
@testable import SwiftCodeCompletion
@testable import SwiftCodeIDECore
@testable import SwiftCodeUI

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
@Suite(.serialized) struct PredictiveCompletionUITests {
    static let deadline: TimeInterval = 60

    func editor(_ name: String, _ text: String, server: StandInServer, debounce: Int = 0) throws -> (SourceEditorController, NSWindow) {
        _ = NSApplication.shared
        var s = PredictiveCompletionSettings()
        s.enabled = true
        s.address = server.baseURL
        s.model = server.modelName
        s.debounceMilliseconds = debounce
        let dir = swiftcodeDir.appendingPathComponent(".build-ide/predict")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        let e = SourceEditorController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = e
        try e.open(file)
        e.predictionSettingsOverride = s
        let address = server.baseURL
        e.predictionSession.makeBackend = { _, _ in OllamaFIMBackend(address: address) }
        e.predictionSession.unreachableBackoff = 0
        window.makeFirstResponder(e.textView)
        return (e, window)
    }

    func key(_ chars: String, code: UInt16, flags: NSEvent.ModifierFlags = [], into tv: NSTextView) {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: tv.window?.windowNumber ?? 0,
                                 context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        tv.keyDown(with: e)
    }

    func type(_ s: String, into tv: NSTextView) { for ch in s { key(String(ch), code: 0, into: tv) } }
    func tab(_ tv: NSTextView, _ flags: NSEvent.ModifierFlags = []) { key("\t", code: 48, flags: flags, into: tv) }
    func escape(_ tv: NSTextView) { key("\u{1b}", code: 53, into: tv) }

    @discardableResult
    func waitFor(_ cond: () -> Bool, timeout: TimeInterval = Self.deadline) async -> Bool {
        var waited = 0.0
        while !cond() {
            if waited > timeout || Task.isCancelled { return false }
            let start = Date()
            try? await Task.sleep(nanoseconds: 5_000_000)
            waited += min(Date().timeIntervalSince(start), 0.25)
        }
        return true
    }

    func state(_ e: SourceEditorController, _ server: StandInServer) -> Comment {
        let p = e.predictionSession
        return "status \(p.status), requests \(p.requestCount), busy \(p.isBusy), server saw \(server.generationRequests.count), suggestion \(String(describing: p.suggestion)), text \(e.text.debugDescription)"
    }

    func caretText(_ e: SourceEditorController) -> String {
        (e.text as NSString).replacingCharacters(in: NSRange(location: e.textView.selectedRange().location, length: 0), with: "|")
    }

    @Test func ghostTextAppearsTabAcceptsEscapeDismisses() async throws {
        let server = try StandInServer { _, _ in "items.count\nprint(total)" }
        let (e, _) = try editor("Ghost.swift", "\n", server: server)
        let tv = e.textView
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        type("let total =", into: tv)
        type(" ", into: tv)
        let appeared = await waitFor { e.predictionSuggestion?.text == "items.count\nprint(total)" }
        try #require(appeared, state(e, server))
        #expect(e.predictionSuggestion?.anchor == 12)
        #expect(e.shownPredictionText == "items.count")
        #expect(tv.ghostOverlay.superview === tv && tv.subviews.last === tv.ghostOverlay)
        let withGhost = try #require(snapshot(tv))
        let saved = tv.ghostText
        tv.ghostText = nil
        #expect(tv.ghostOverlay.superview == nil)
        let without = try #require(snapshot(tv))
        tv.ghostText = saved
        #expect(withGhost != without)
        if let out = ProcessInfo.processInfo.environment["SWIFTCODE_PREDICT_SNAPSHOT"] { try withGhost.write(to: URL(fileURLWithPath: out)) }
        tv.flagsChanged(with: NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .option, timestamp: 0, windowNumber: tv.window?.windowNumber ?? 0,
                                               context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)!)
        #expect(e.shownPredictionText == "items.count\nprint(total)")
        let expanded = try #require(snapshot(tv))
        #expect(expanded != withGhost)
        if let out = ProcessInfo.processInfo.environment["SWIFTCODE_PREDICT_SNAPSHOT"] { try expanded.write(to: URL(fileURLWithPath: out + ".expanded.tiff")) }
        tv.flagsChanged(with: NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: tv.window?.windowNumber ?? 0,
                                               context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)!)
        tab(tv)
        #expect(caretText(e) == "let total = items.count|\n")
        #expect(e.predictionSuggestion?.text == "\nprint(total)")
        escape(tv)
        #expect(e.predictionSuggestion == nil)
        #expect(e.text == "let total = items.count\n")
        #expect(e.isDirty)
    }

    @Test func typingThroughOptionTabAndControlTab() async throws {
        let server = try StandInServer { _, _ in "compute(value: 42)\nreturn" }
        let (e, _) = try editor("Through.swift", "\n", server: server)
        let tv = e.textView
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        type("let r = ", into: tv)
        let appeared = await waitFor { e.predictionSuggestion?.text == "compute(value: 42)\nreturn" && !e.predictionSession.isBusy }
        try #require(appeared, state(e, server))
        let requests = server.generationRequests.count
        type("comp", into: tv)
        #expect(e.predictionSuggestion?.text == "ute(value: 42)\nreturn")
        #expect(e.predictionSuggestion?.anchor == 12)
        tab(tv, .control)
        #expect(caretText(e) == "let r = compute|\n")
        #expect(e.predictionSuggestion?.text == "(value: 42)\nreturn")
        tab(tv, .option)
        #expect(caretText(e) == "let r = compute(value: 42)\nreturn|\n")
        #expect(e.predictionSuggestion == nil)
        #expect(server.generationRequests.count == requests)
    }

    @Test func typingSomethingElseAndMovingTheCaretDrop() async throws {
        let server = try StandInServer { _, _ in "abc" }
        let (e, _) = try editor("Drop.swift", "let a = 1\n\n", server: server)
        let tv = e.textView
        tv.setSelectedRange(NSRange(location: 10, length: 0))
        type("x", into: tv)
        let ready1 = await waitFor { e.predictionSuggestion != nil }
        try #require(ready1, state(e, server))
        type("z", into: tv)
        #expect(e.predictionSuggestion == nil || e.predictionSuggestion?.anchor == 12)
        let ready2 = await waitFor { e.predictionSuggestion?.anchor == 12 }
        try #require(ready2, state(e, server))
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(e.predictionSuggestion == nil)
        tv.setSelectedRange(NSRange(location: 10, length: 0))
        let before = e.text
        tab(tv)
        #expect(e.text != before)
        let indented = e.text
        escape(tv)
        #expect(e.text == indented && e.predictionSuggestion == nil)
    }

    @Test func showPredictiveCompletionAsksMidLineAndOffDoesNothing() async throws {
        let server = try StandInServer { _, _ in "Int" }
        let (e, _) = try editor("Command.swift", "let n: = 1\n", server: server)
        let tv = e.textView
        tv.setSelectedRange(NSRange(location: 7, length: 0))
        #expect(NSApp.sendAction(NSSelectorFromString("showPredictiveCompletion:"), to: tv, from: nil))
        let ready3 = await waitFor { e.predictionSuggestion != nil }
        try #require(ready3, state(e, server))
        #expect(e.predictionSuggestion == .init(anchor: 7, text: "Int"))
        let mid = try #require(snapshot(tv))
        if let out = ProcessInfo.processInfo.environment["SWIFTCODE_PREDICT_SNAPSHOT"] { try mid.write(to: URL(fileURLWithPath: out + ".mid.tiff")) }
        escape(tv)
        var s = try #require(e.predictionSettingsOverride)
        s.enabled = false
        e.predictionSettingsOverride = s
        let n = server.generationRequests.count
        tv.setSelectedRange(NSRange(location: 11, length: 0))
        let asked = e.predictionSession.requestCount
        type("x", into: tv)
        #expect(!e.predictionSession.isBusy && e.predictionSession.requestCount == asked && e.predictionSuggestion == nil)
        #expect(server.generationRequests.count == n)
    }

    @Test func settingsRowsAndTest() async throws {
        let defaults = TestDefaults("predict-settings")
        defer { defaults.remove() }
        let p = Preferences(defaults: defaults.defaults, themesDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-predict-themes-\(UUID().uuidString)"))
        let server = try StandInServer { _, _ in "" }
        let pane = TextEditingSettingsPane(prefs: p)
        _ = pane.view
        #expect(pane.rowTitles.contains("Predictive code completion"))
        pane.toggle("Predictive code completion")
        #expect(p.predictiveCompletion.enabled)
        pane.page = .completion
        for row in ["# Predictive Code Completion", "Backend", "Address", "Model", "Test", "Download a model", "Wait after typing (ms)", "Most tokens", "Temperature"] {
            #expect(pane.rowTitles.contains(row), "\(row)")
        }
        #expect(pane.control(NSPopUpButton.self, inRow: "Backend")?.itemTitles == ["Ollama", "llama.cpp server", "OpenAI-compatible server"])
        let address = try #require(pane.control(NSTextField.self, inRow: "Address"))
        #expect(address.placeholderString == "http://127.0.0.1:11434")
        pane.updatePrediction { $0.address = server.baseURL }
        var done = false
        pane.testPrediction { done = true }
        await waitFor { done }
        #expect(pane.predictionMessage == "Ollama is running: 1 of 1 models can fill in the middle.")
        #expect(pane.control(NSPopUpButton.self, inRow: "Model")?.itemTitles == ["Automatic", "stand-in-coder"])
        pane.choose("stand-in-coder", inRow: "Model")
        #expect(p.predictiveCompletion.model == "stand-in-coder")
        pane.choose("llama.cpp server", inRow: "Backend")
        #expect(p.predictiveCompletion.backend == .llamaServer)
        #expect(p.predictiveCompletion.address == nil && p.predictiveCompletion.model.isEmpty)
        #expect(!pane.rowTitles.contains("Download a model"))
        pane.choose("Ollama", inRow: "Backend")
        pane.updatePrediction { $0.address = "http://127.0.0.1:1" }
        done = false
        pane.testPrediction { done = true }
        await waitFor { done }
        #expect(pane.predictionMessage.contains("ollama.com/download"))
        #expect(pane.control(NSButton.self, inRow: "Get Ollama…") != nil)
    }

    @Test func activityNoticeIsQuiet() {
        #expect(WorkspaceWindowController.predictionActivityText(.unavailable(message: "Ollama is not running at http://127.0.0.1:11434.", hint: nil))
                == "Predictive completion: Ollama is not running at http://127.0.0.1:11434.")
        #expect(WorkspaceWindowController.predictionActivityText(.ready(model: "m")) == nil)
        #expect(WorkspaceWindowController.predictionActivityText(.requesting) == nil)
    }

    func snapshot(_ v: NSView) -> Data? {
        v.window?.contentView?.layoutSubtreeIfNeeded()
        if v.bounds.width < 100 { v.setFrameSize(NSSize(width: 700, height: max(v.bounds.height, 100))) }
        let r = NSRect(x: 0, y: 0, width: max(1, min(v.bounds.width, 600)), height: 80)
        guard let rep = v.bitmapImageRepForCachingDisplay(in: r) else { return nil }
        v.cacheDisplay(in: r, to: rep)
        return rep.tiffRepresentation
    }
}
