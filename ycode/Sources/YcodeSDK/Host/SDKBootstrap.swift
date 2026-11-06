import Foundation

// MARK: - SDKBootstrap
//
// Ported from Legacy `SwiftCode/SDK/Host/SDKBootstrap.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// One-time SDK host bootstrap. Idempotent: a second call is a no-op.
// Registers the built-in view openers and the Assist view opener, and
// scans the extension registry so installed extensions are known.
//
// Legacy also started `SDKExtensionManager.startAll()` here; that
// manager is DROPPED by design — the v2 `ExtensionManager` owns
// extension lifecycle in Ycode (spec §3.4 crash policy: stop after 3,
// manual retry). Bootstrap deliberately does not start any runtime.
//
// Failures are loud (OS log) and the "done" flag stays unset, so a
// later call retries.

@MainActor
public enum SDKBootstrap {
    private static var bootstrapped = false

    public static func bootstrapIfNeeded() async {
        guard !bootstrapped else { return }
        SDKViewOpenerBuiltIns.registerBuiltInOpeners()
        SDKAssistUIOpener.registerAssistViewOpener()
        // The scan never throws: malformed entries are skipped and logged.
        await SDKExtensionRegistry.shared.scan()
        bootstrapped = true
    }
}
