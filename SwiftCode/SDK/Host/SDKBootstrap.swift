import Foundation
import os.log

// MARK: - SDKBootstrap
//
// The single startup call site for the SwiftCode SDK host side.
//
// Call `await SDKBootstrap.bootstrapIfNeeded()` exactly once from the
// app's launch path (`SwiftCodeApp.init()` — the one existing call site).
// It installs every one-time SDK host registration that must exist before
// any extension session can run. Today that is the built-in view-opener
// table (`SDKViewOpenerBuiltIns.registerBuiltInOpeners()`); any future
// one-time SDK setup belongs here too, so app-launch code never needs a
// second SDK call site.
//
// ## Guarantees
//
// - Runs at most once per process: the whole enum is `@MainActor`, so the
//   check-and-set of `didBootstrap` cannot race — a second call (even
//   concurrent) is a cheap no-op.
// - Runs on the main actor: registrations touch UI (`NSWindow` managers,
//   the `.toolbarToolActivated` notification bridge) and several of the
//   singletons they touch are `@MainActor`-isolated. Callers may invoke
//   `bootstrapIfNeeded()` from any isolation; the `await` hops here.
// - Fails loud, degrades typed: `registerBuiltInOpeners()` throws a typed
//   `SDKError` (never a silent no-op) when a bridge `toolID` no longer
//   resolves. The failure is logged via `os.log` rather than thrown out of
//   the bootstrap, so a broken opener table cannot crash the host app at
//   launch — but the flag stays unset, so a later call retries instead of
//   leaving the SDK silently half-initialized. Meanwhile, until the table
//   installs, every extension `ui.openView` throws typed
//   `.serviceUnavailable` (see `SDKViewOpener.open(viewID:)`): loud for
//   the extension, never a silent no-op.

@MainActor
public enum SDKBootstrap {

    /// Whether the one-time registrations have completed. Main-actor
    /// isolated, so the check-and-set is race-free by construction.
    private static var didBootstrap = false

    private static let logger = Logger(
        subsystem: "com.swiftcode.app",
        category: "SDKBootstrap"
    )

    /// Runs the one-time SDK host registrations if they have not run yet.
    /// Idempotent and safe to call from any isolation.
    public static func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        do {
            logger.debug("SDKBootstrap: installing one-time host registrations")

            // View capability registry (SDKViewOpenerBuiltIns.swift): the
            // ten built-in view openers. Must run before any extension can
            // call `ui.openView` — unregistered view IDs throw
            // `.serviceUnavailable` by design.
            try await SDKViewOpener.shared.registerBuiltInOpeners()

            // Extension/app supervisor (SDKExtensionManager.swift): discovers
            // installed packages in ~/.swiftcode/extensions, validates each
            // manifest, and launches + supervises the enabled ones (real
            // lifecycle: crash retries with backoff, quarantine, cleanup).
            // Never throws out of bootstrap: one broken extension must not
            // prevent the rest from starting or break app launch.
            let summary = await SDKExtensionManager.shared.startAll()
            if !summary.started.isEmpty {
                logger.debug("SDKBootstrap: started \(summary.started.count, privacy: .public) extension(s)")
            }
            for skipped in summary.skipped {
                logger.debug("SDKBootstrap: skipped '\(skipped.id, privacy: .public)': \(skipped.reason, privacy: .public)")
            }
            for failed in summary.failed {
                logger.error("SDKBootstrap: failed to start '\(failed.id, privacy: .public)': \(failed.reason, privacy: .public)")
            }

            // Future one-time SDK registrations belong here.

            // Assist main view opener (SDKAssistUIOpener): registers the
            // real AssistMainView for the agreed viewId "assist.main"
            // (assist.viewId rule, task B2). Registered here rather than in
            // SDKViewOpenerBuiltIns so the scopes-sync contract (every
            // BuiltIns opener needs a kind:"view" ScopesIDLists entry)
            // stays green while `assist.ui` is an API-kind entry.
            // Never throws out of bootstrap: a failed registration must
            // not break app launch; the opener simply stays unregistered
            // and `open` throws typed `.serviceUnavailable`.
            await SDKAssistUIOpener.registerAssistViewOpener()

            didBootstrap = true
            logger.debug("SDKBootstrap: complete")
        } catch {
            logger.error("SDKBootstrap failed: \(error.localizedDescription, privacy: .public)")
            logger.error("ui.openView will throw .serviceUnavailable until a later call succeeds.")
        }
    }
}
