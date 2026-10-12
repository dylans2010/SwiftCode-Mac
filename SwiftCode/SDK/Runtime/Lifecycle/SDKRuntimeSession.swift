import Foundation

// MARK: - SDKRuntimeSessionInfo
//
// Identity + provenance snapshot for one extension runtime session. The host
// coordinator (a LATER phase) creates one of these per discovered extension
// and hands it to `SDKRuntimeSession`.
//
// Owned by this file. Sibling SDK subagents code against this exact shape.

public struct SDKRuntimeSessionInfo: Sendable {
    /// Host-minted session identifier. Never taken from the extension — it is
    /// bound to this session at the IPC boundary (spec §10).
    public let sessionID: UUID
    /// The validated extension id (reverse-DNS, from the manifest).
    public let extensionID: String
    /// Hex digest of the installed package (e.g. SHA-256 of the package
    /// bundle at discovery time). Lets the host detect on-disk tampering
    /// between discovery and launch.
    public let packageDigest: String
    /// Filesystem root the extension package was installed under. Used to
    /// scope capability grants; never handed to the extension as a writable
    /// path unless a capability explicitly allows it.
    public let projectRootPath: String
    /// The validated manifest (data only; validation lives in
    /// `SDKManifestValidator` / `SDKPackageValidator`).
    public let manifest: SDKManifest
    /// Developer API key secret presented for this session, if any (spec
    /// §8.2.1). Set by the host coordinator from
    /// `SDKAPIKeySessionAuth.presentedKeyFromEnvironment()` — i.e. the
    /// `SWIFTCODE_API_KEY` environment variable. This is the session's
    /// handshake credential: `SDKIPCDispatcher` verifies it against
    /// `SDKAPIKeyStore` on every request the session makes, failing closed
    /// with `.apiKeyInvalid` when verification fails. It is never
    /// persisted, never logged, and never leaves host memory.
    ///
    /// Nil (the default) means the session presents no key and authorizes
    /// purely through user grants.
    public let presentedAPIKey: String?

    public init(
        sessionID: UUID = UUID(),
        extensionID: String,
        packageDigest: String,
        projectRootPath: String,
        manifest: SDKManifest,
        presentedAPIKey: String? = nil
    ) {
        self.sessionID = sessionID
        self.extensionID = extensionID
        self.packageDigest = packageDigest
        self.projectRootPath = projectRootPath
        self.manifest = manifest
        self.presentedAPIKey = presentedAPIKey
    }
}

// MARK: - SDKRuntimeState
//
// Lifecycle states (spec §10.5). The machine is strict: only the transitions
// enumerated by `SDKRuntimeSession.legalSuccessors(of:)` are permitted;
// anything else throws.
//
// Forward flow:
//   discovered → validated → awaitingPermission → ready → starting → active
//   → stopping → stopped
//
// Failure states (reached from ANY state):
//   failedValidation, failedVersion, permissionDenied, launchFailed,
//   activationFailed, crashed, timedOut, terminated
//
// Terminal states (no legal *forward* exit; a crash audit record is written
// once on entry): stopped, crashed, timedOut, terminated, failedValidation,
// failedVersion, permissionDenied, launchFailed, activationFailed.

public enum SDKRuntimeState: String, Sendable, CaseIterable {
    // Forward flow
    case discovered
    case validated
    case awaitingPermission
    case ready
    case starting
    case active
    case stopping
    case stopped

    // Failure states
    case failedValidation
    case failedVersion
    case permissionDenied
    case launchFailed
    case activationFailed
    case crashed
    case timedOut
    case terminated
}

// MARK: - SDKRuntimeSession
//
// The lifecycle STATE MACHINE for one extension runtime (spec §10.5). It
// records state, enforces the legal transition map, counts crashes (bounded
// restarts), runs the owner-supplied teardown hook, and audit-records every
// terminal entry.
//
// This is the state machine ONLY. The DRIVER that moves sessions through it —
// the host coordinator that spawns the runtime process, pipes IPC, and calls
// `transition(to:)` — arrives in a later phase. This file never spawns
// processes, never opens IPC channels, and never launches anything: it is
// pure lifecycle bookkeeping.
//
// Actor isolation gives the driver serialized, race-free state changes for
// free (Swift 6 strict concurrency).

public actor SDKRuntimeSession {
    /// Maximum crashes before a restart is refused. Bounded restarts are a
    /// spec §10.5 requirement: "never enter an infinite crash/restart loop".
    public static let maxCrashRestarts = 3

    /// Session identity/provenance. Immutable; safe to read without the actor.
    public nonisolated let info: SDKRuntimeSessionInfo

    /// Owner-supplied teardown hook, installed by the driver before launch.
    /// Run exactly once by `deactivate()`: the owner disposes extension-owned
    /// resources here — commands, event subscriptions, build handles,
    /// streams, IPC handles, and cancelled operations (spec §10.5:
    /// "Deactivation disposes commands, event subscriptions, build handles,
    /// and other extension-owned resources").
    ///
    /// Actor-isolated; assign from the driver with `await`.
    public var onDeactivate: (@Sendable () async -> Void)?

    private var currentState: SDKRuntimeState
    private var history: [(state: SDKRuntimeState, at: Date)] = []
    private var crashTotal = 0

    // MARK: - Init

    /// Creates the session in `.discovered`. The driver then walks it through
    /// the forward flow as the package is validated, permissions are granted,
    /// and the runtime launches.
    public init(info: SDKRuntimeSessionInfo) {
        self.info = info
        self.currentState = .discovered
        self.history = [(state: .discovered, at: Date())]
    }

    // MARK: - State reads

    /// Current lifecycle state.
    public var state: SDKRuntimeState { currentState }

    /// Append-only history of every state, in entry order, for diagnostics.
    /// Never rewritten — failures are recorded by appending the failure
    /// state, never by mutating earlier entries.
    public var stateHistory: [(state: SDKRuntimeState, at: Date)] { history }

    /// Total crashes recorded via `markCrashed(exitCode:)`.
    public var crashCount: Int { crashTotal }

    /// Whether the driver may attempt another launch. Becomes `false` after
    /// `maxCrashRestarts` crashes — the driver must NOT relaunch beyond that
    /// (spec §10.5: restart behavior must be explicit; never an infinite
    /// crash/restart loop).
    public var canRestart: Bool { crashTotal < Self.maxCrashRestarts }

    /// Whether the session is in a terminal state.
    public var isTerminal: Bool { Self.isTerminal(currentState) }

    // MARK: - Transitions

    /// The legal transition map. Read-only; computed from the state so the
    /// map lives in exactly one place.
    ///
    /// Rules:
    ///   - Forward flow is strictly linear:
    ///     discovered→validated→awaitingPermission→ready→starting→active→
    ///     stopping→stopped. A stop may also be requested while starting, so
    ///     starting→stopping is legal.
    ///   - Double activation is rejected: ready→starting is the single
    ///     forward step; starting→starting, active→starting and any other
    ///     re-entry is illegal. A re-launch of a terminated session uses a
    ///     NEW `SDKRuntimeSession` (fresh `.discovered` history), never a
    ///     backward transition.
    ///   - Any state may move to any failure state
    ///     (failedValidation/failedVersion/permissionDenied/launchFailed/
    ///     activationFailed/crashed/timedOut/terminated). That includes a
    ///     terminal state reaching another failure state (e.g. a crashed
    ///     session's forced termination), but a terminal state never returns
    ///     to a forward-flow state.
    public static func legalSuccessors(of state: SDKRuntimeState) -> Set<SDKRuntimeState> {
        var successors: Set<SDKRuntimeState> = []
        switch state {
        case .discovered:
            successors.insert(.validated)
        case .validated:
            successors.insert(.awaitingPermission)
        case .awaitingPermission:
            successors.insert(.ready)
        case .ready:
            successors.insert(.starting)
        case .starting:
            successors.formUnion([.active, .stopping])
        case .active:
            successors.insert(.stopping)
        case .stopping:
            successors.insert(.stopped)
        case .stopped, .crashed, .timedOut, .terminated,
             .failedValidation, .failedVersion, .permissionDenied,
             .launchFailed, .activationFailed:
            break // terminal: no forward successors
        }
        // Failure states are reachable from any state, including terminal
        // ones (a crash or forced termination can still be recorded after
        // another failure).
        successors.formUnion(Self.failureStates)
        return successors
    }

    /// Moves to `newState`, enforcing the legal transition map.
    ///
    /// - Throws: `SDKError(code: .activationFailed, …)` naming the illegal
    ///   "from X to Y" pair. The message is user-safe (state names and the
    ///   extension id only); the diagnostics dictionary carries the same
    ///   values for the developer log.
    public func transition(to newState: SDKRuntimeState) throws {
        try apply(newState, auditDetail: nil)
    }

    // MARK: - Crash accounting

    /// Records a runtime crash. Moves the session to `.crashed` (legal from
    /// any state, including a `.crashed` re-entry), increments the crash
    /// count, and audit-records the event with the exit code. The count
    /// increments even on a same-state re-entry, so restart accounting never
    /// lies and the audit record is not duplicated for the re-entry.
    ///
    /// Per spec §10.5, a crash marks the extension failed; the driver
    /// (later phase) is responsible for removing its contributions,
    /// cancelling eligible operations, and reporting actionable diagnostics.
    /// The driver consults `canRestart` before any relaunch — this function
    /// does NOT relaunch by itself, and `canRestart` caps relaunches at
    /// `maxCrashRestarts`, so an infinite crash/restart loop is impossible.
    public func markCrashed(exitCode: Int32) {
        crashTotal += 1
        let detail = "Runtime crashed with exit code \(exitCode); "
            + "crash #\(crashTotal) of \(Self.maxCrashRestarts) allowed"
        try? apply(.crashed, auditDetail: detail)
    }

    // MARK: - Stop / deactivate

    /// Requests a graceful stop. Legal from `.active` and `.starting`
    /// (the only legal predecessors of `.stopping`). Idempotent: calling it
    /// while already `.stopping` is a no-op, and it is a no-op from terminal
    /// states (nothing is running) and from pre-launch states (nothing to
    /// stop yet — the driver should drive those to a failure state
    /// instead, e.g. `.terminated` on app shutdown).
    public func requestStop() {
        switch currentState {
        case .active, .starting:
            try? apply(.stopping, auditDetail: nil)
        case .stopping:
            break // idempotent: already stopping
        default:
            break // terminal or pre-launch: nothing to stop
        }
    }

    /// Runs the owner's teardown hook exactly once, then moves the session to
    /// `.stopped` through the legal map.
    ///
    /// Path: if the session is live (`.starting`/`.active`) it first moves to
    /// `.stopping`; the hook runs (commands disposed, streams closed,
    /// handles cancelled — by the OWNER, see `onDeactivate`); then it moves
    /// to `.stopped`, which audit-records the termination. If the session is
    /// already terminal, the hook still runs exactly once if it has not run,
    /// and the state is left untouched (there is no legal path out of a
    /// terminal state into `.stopped` other than re-recording a failure,
    /// which would corrupt the append-only history). Pre-launch states
    /// (`.discovered`/`.validated`/`.awaitingPermission`/`.ready`) never
    /// launched anything, so the hook runs but the state is left alone —
    /// the driver should retire such sessions with a failure transition
    /// (e.g. `.terminated` on app shutdown) instead.
    ///
    /// Spec §10.5: "Activation failure triggers best-effort deactivation and
    /// cleanup" and "App shutdown must stop extensions within bounded time" —
    /// the bounded-time enforcement (timeout → `.timedOut`) is the driver's
    /// job; this function performs the ordered teardown itself.
    public func deactivate() async {
        switch currentState {
        case .starting, .active:
            try? apply(.stopping, auditDetail: nil)
        case .stopping:
            break
        default:
            break // pre-launch: nothing was launched; terminal: nothing left
        }

        if let hook = onDeactivate {
            onDeactivate = nil // exactly-once, even if the hook throws out
            await hook()
        }

        if currentState == .stopping {
            try? apply(.stopped, auditDetail: nil)
        }
    }

    // MARK: - Private

    /// All failure states, reachable from any state per `legalSuccessors`.
    private static let failureStates: Set<SDKRuntimeState> = [
        .failedValidation, .failedVersion, .permissionDenied,
        .launchFailed, .activationFailed, .crashed, .timedOut, .terminated,
    ]

    /// Terminal states: audit-recorded once on entry; no forward exit.
    private static let terminalStates: Set<SDKRuntimeState> = [
        .stopped, .crashed, .timedOut, .terminated,
        .failedValidation, .failedVersion, .permissionDenied,
        .launchFailed, .activationFailed,
    ]

    private static func isTerminal(_ state: SDKRuntimeState) -> Bool {
        terminalStates.contains(state)
    }

    /// Single choke point for every state change. Validates against the legal
    /// map, appends to the append-only history, and audit-records the first
    /// entry into a terminal state (`.runtimeTerminated` with the extension
    /// id and a detail naming the state — never secrets).
    private func apply(_ newState: SDKRuntimeState, auditDetail: String?) throws {
        guard Self.legalSuccessors(of: currentState).contains(newState) else {
            throw SDKError(
                code: .activationFailed,
                message: "Illegal lifecycle transition from "
                    + "\(currentState.rawValue) to \(newState.rawValue)",
                suggestion: "This is a host-driver bug or a race in the "
                    + "extension coordinator: the session can only move "
                    + "through the documented lifecycle states.",
                diagnostics: [
                    "from": currentState.rawValue,
                    "to": newState.rawValue,
                    "extensionID": info.extensionID,
                    "sessionID": info.sessionID.uuidString,
                ]
            )
        }

        let previous = currentState
        currentState = newState
        history.append((state: newState, at: Date()))

        // Terminal entry → audit-record once. A terminal→terminal failure
        // move (e.g. crashed→terminated) is a distinct security-relevant
        // fact about the session's end, so it records again; a same-state
        // re-entry (e.g. markCrashed on an already-.crashed session) does not
        // re-record.
        if Self.isTerminal(newState)
            && (!Self.isTerminal(previous) || newState != previous)
        {
            let detail = auditDetail
                ?? "Session reached terminal state \(newState.rawValue)"
            // Best-effort: SDKAuditLog.record never throws or traps outward.
            // Fire-and-forget because `transition(to:)` is synchronous by
            // contract — audit durability is the log's own responsibility.
            Task { [info] in
                await SDKAuditLog.shared.record(
                    type: .runtimeTerminated,
                    extensionID: info.extensionID,
                    detail: detail
                )
            }
        }
    }
}
