import Foundation
import os.log

// MARK: - SDKManagedExtension
//
// The Studio/UI-facing snapshot of one discovered extension: identity and
// version from the validated manifest, host-managed enablement, the live
// lifecycle state, and the last actionable diagnostic. Data only — all
// mutation goes through `SDKExtensionManager`.

public struct SDKManagedExtension: Sendable {
    public let id: String
    public let name: String
    public let version: String
    /// Absolute path of the installed package directory.
    public let installPath: String
    /// SHA-256 hex digest of the installed tree at discovery time.
    public let packageDigest: String
    /// The validated manifest (nil when validation failed).
    public let manifest: SDKManifest?
    /// Host-managed enabled flag (user toggle). Disabled extensions are
    /// never launched.
    public let enabled: Bool
    /// Current lifecycle state (`.discovered` for never-launched packages).
    public let lifecycleState: SDKRuntimeState
    /// Crashes recorded this process lifetime (drives the retry bound).
    public let crashCount: Int
    /// True when the manager quarantined the extension: it stays stopped
    /// until the user re-enables or reinstalls it.
    public let quarantined: Bool
    /// Actionable diagnostic for stopped/invalid extensions; nil when the
    /// extension is healthy or running.
    public let diagnostic: String?

    /// Commands declared in the manifest's `contributes` section. Invoking
    /// one routes through the TS runtime (`commands.execute` host event),
    /// never native injection.
    public var declaredCommands: [SDKManifestCommandContribution] {
        manifest?.contributes?.commands ?? []
    }
}

// MARK: - SDKExtensionLaunchSummary
//
// Result of `startAll()` (called from `SDKBootstrap` at app launch).

public struct SDKExtensionLaunchSummary: Sendable {
    public let started: [String]
    public let skipped: [(id: String, reason: String)]
    public let failed: [(id: String, reason: String)]
}

// MARK: - SDKExtensionManager
//
// The host-side extension/app supervisor (Docs/Intro-to-SDK.md §6): the
// single service that starts and supervises ALL installed extensions/apps.
//
// This is THE driver that `SDKRuntimeSession` was written for (see that
// file's header): it discovers packages in the controlled extensions
// directory, validates each manifest with `SDKManifestValidator`, spawns
// one out-of-process node runtime per enabled extension via
// `SDKNodeLauncher`, pipes IPC through `SDKIPCTransport` /
// `SDKIPCDispatcher`, and walks every session through the strict lifecycle
// state machine.
//
// Layout of the controlled directory (`~/.swiftcode/extensions`):
//   <root>/<extension-id>/swiftcode.json   — the validated manifest
//   <root>/<extension-id>/...              — the installed package tree
//   <root>/.host-state.json                — host-managed per-extension
//                                          state (enabled flag, recorded
//                                          digest, quarantine). Extension
//                                          code must never write here.
//
// Crash policy (spec §10.5): an unexpected runtime exit is recorded with
// `markCrashed(exitCode:)`; while the manager-side crash count stays below
// `SDKRuntimeSession.maxCrashRestarts` the extension is relaunched with
// exponential backoff (2s, 4s, 8s); afterwards it is QUARANTINED —
// stopped, diagnosed to the user, contributions removed — and never
// relaunched until the user intervenes. An infinite crash/restart loop is
// structurally impossible: the bound is enforced by the manager's own
// per-extension counter, which survives session replacement (a relaunch
// always uses a NEW `SDKRuntimeSession` per the lifecycle rules).
//
// An actor, so all runtime bookkeeping is serialized and race-free under
// Swift 6 strict concurrency.

public actor SDKExtensionManager {

    // MARK: - Shared instance

    public static let shared = SDKExtensionManager()

    // MARK: - Layout

    /// The controlled extensions directory. Created on demand.
    public nonisolated static var extensionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swiftcode/extensions", isDirectory: true)
    }

    private static let manifestFileName = "swiftcode.json"
    private static let stateFileName = ".host-state.json"

    /// Activation budget: the runtime adapter must emit `extension.ready`
    /// within this window after spawn, or the session times out.
    private static let activationTimeoutNanoseconds: UInt64 = 30_000_000_000
    /// Budget for one command invocation round-trip.
    private static let commandTimeoutNanoseconds: UInt64 = 60_000_000_000
    /// Bounded stop budget per extension on disable/uninstall.
    private static let stopTimeoutNanoseconds: UInt64 = 10_000_000_000
    /// Backoff cap for crash restarts (2s, 4s, 8s, … capped here).
    private static let maxRestartBackoffSeconds: UInt64 = 30

    private static let log = Logger(
        subsystem: "com.swiftcode.sdk",
        category: "sdk-extension-manager"
    )

    private init() {}

    // MARK: - Persistent host state

    /// Host-managed per-extension state, persisted at
    /// `<root>/.host-state.json`. Extensions never write here.
    private struct HostExtensionState: Codable, Sendable {
        var enabled: Bool = true
        /// Digest recorded at the last clean scan; a mismatch means the
        /// package changed on disk (tamper or manual edit) and forces
        /// quarantine + grant revocation per spec §8.7.
        var recordedDigest: String?
        var quarantined: Bool = false
        var quarantineReason: String?
    }

    private var persistedState: [String: HostExtensionState] = [:]
    private var stateLoaded = false

    private func loadPersistedState() {
        guard !stateLoaded else { return }
        stateLoaded = true
        let url = Self.extensionsRoot.appendingPathComponent(Self.stateFileName)
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode([String: HostExtensionState].self, from: data) {
            persistedState = decoded
        }
    }

    private func savePersistedState() {
        let url = Self.extensionsRoot.appendingPathComponent(Self.stateFileName)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(persistedState)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Self.log.error("SDKExtensionManager: failed to persist host state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func state(for id: String) -> HostExtensionState {
        loadPersistedState()
        return persistedState[id] ?? HostExtensionState()
    }

    private func setState(_ newState: HostExtensionState, for id: String) {
        loadPersistedState()
        persistedState[id] = newState
        savePersistedState()
    }

    // MARK: - Live runtime bookkeeping

    /// Everything the manager owns for one launched extension.
    private struct RuntimeHandle {
        var session: SDKRuntimeSession
        var launched: SDKLaunchedRuntime
        var transport: SDKIPCTransport
        var dispatcher: SDKIPCDispatcher
        var ioTask: Task<Void, Never>
        var terminationTask: Task<Void, Never>
    }

    /// extensionID -> live runtime. A missing entry means "not running".
    private var handles: [String: RuntimeHandle] = [:]
    /// Manager-side crash counts (survive session replacement — this is
    /// what bounds restarts).
    private var crashCounts: [String: Int] = [:]
    /// Last actionable diagnostic per extension, for the UI.
    private var diagnostics: [String: String] = [:]
    /// Pending `commands.execute` invocations, keyed by invocation ID.
    private var pendingInvocations: [String: (extensionID: String, continuation: CheckedContinuation<SDKJSONValue, Error>)] = [:]
    /// Pending activation handshakes, keyed by extension ID.
    private var activationWaiters: [String: CheckedContinuation<Void, Error>] = [:]

    // MARK: - Discovery

    /// One discovered package directory: the validated manifest (or the
    /// validation error) plus identity fields.
    private struct DiscoveredPackage {
        let id: String
        let installPath: URL
        let manifest: SDKManifest?
        let digest: String?
        let validationError: SDKError?
    }

    private func ensureExtensionsRoot() throws {
        let root = Self.extensionsRoot
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw SDKError(
                    code: .installFailed,
                    message: "The extensions directory exists but is not a directory.",
                    suggestion: "Remove the file at ~/.swiftcode/extensions and relaunch SwiftCode."
                )
            }
            return
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw SDKError(
                code: .installFailed,
                message: "Could not create the extensions directory.",
                suggestion: "Check that your home directory is writable and relaunch SwiftCode.",
                diagnostics: ["ioError": String(describing: error)]
            )
        }
    }

    /// Reads every `<root>/<id>/` directory, validates each `swiftcode.json`
    /// with `SDKManifestValidator`, and returns the packages sorted by id.
    /// Invalid packages are RETURNED (with `validationError` set) — never
    /// silently dropped — so the UI can show actionable diagnostics.
    private func discover() async throws -> [DiscoveredPackage] {
        try ensureExtensionsRoot()
        let root = Self.extensionsRoot
        let fileManager = FileManager.default

        let idNames: [String]
        do {
            idNames = try fileManager.contentsOfDirectory(atPath: root.path)
        } catch {
            throw SDKError(
                code: .installFailed,
                message: "Could not read the extensions directory.",
                suggestion: "Check the permissions of ~/.swiftcode/extensions and try again.",
                diagnostics: ["ioError": String(describing: error)]
            )
        }

        var found: [DiscoveredPackage] = []
        for idName in idNames.sorted() {
            // The host state file is metadata, not a package.
            guard idName != Self.stateFileName, !idName.hasPrefix(".") else { continue }
            let idDir = root.appendingPathComponent(idName, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: idDir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            found.append(await readPackage(idName: idName, at: idDir))
        }
        return found
    }

    /// Reads and validates one package directory. Never throws: failures are
    /// captured in `DiscoveredPackage.validationError` with an actionable
    /// message, so one broken package can never abort the whole scan.
    private func readPackage(idName: String, at idDir: URL) async -> DiscoveredPackage {
        let manifestURL = idDir.appendingPathComponent(Self.manifestFileName)
        guard let data = try? Data(contentsOf: manifestURL) else {
            return DiscoveredPackage(
                id: idName,
                installPath: idDir,
                manifest: nil,
                digest: nil,
                validationError: SDKError(
                    code: .manifestInvalid,
                    message: "“\(idName)” has no swiftcode.json manifest.",
                    suggestion: "Reinstall the extension, or remove the “\(idName)” directory from ~/.swiftcode/extensions."
                )
            )
        }
        do {
            let manifest = try SDKManifestValidator.validate(data: data)
            guard manifest.id == idName else {
                throw SDKError(
                    code: .manifestInvalid,
                    message: "The manifest id “\(manifest.id)” does not match its install directory “\(idName)”.",
                    suggestion: "Reinstall the extension; the install directory name must equal the manifest id."
                )
            }
            let digest = try? await SDKExtensionRegistry.shared.computeDigest(of: idDir)
            return DiscoveredPackage(
                id: idName, installPath: idDir, manifest: manifest,
                digest: digest, validationError: nil
            )
        } catch let sdkError as SDKError {
            return DiscoveredPackage(
                id: idName, installPath: idDir, manifest: nil,
                digest: nil, validationError: sdkError
            )
        } catch {
            return DiscoveredPackage(
                id: idName, installPath: idDir, manifest: nil,
                digest: nil,
                validationError: SDKError(
                    code: .manifestInvalid,
                    message: "“\(idName)” failed manifest validation.",
                    suggestion: "Reinstall the extension.",
                    diagnostics: ["underlyingError": String(describing: error)]
                )
            )
        }
    }

    // MARK: - Snapshot (UI)

    /// Discovers all packages and merges live runtime state. Used by Studio.
    /// Never throws: discovery failures surface as a single diagnostic row.
    public func snapshot() async -> [SDKManagedExtension] {
        let packages: [DiscoveredPackage]
        do {
            packages = try await discover()
        } catch {
            let message: String
            if let sdkError = error as? SDKError {
                message = sdkError.message
                await SDKUserLogger.shared.log(sdkError)
            } else {
                message = error.localizedDescription
            }
            Self.log.error("SDKExtensionManager: discovery failed: \(message, privacy: .public)")
            return []
        }

        var result: [SDKManagedExtension] = []
        for package in packages {
            let hostState = state(for: package.id)
            let handle = handles[package.id]
            let lifecycleState: SDKRuntimeState
            if let handle {
                lifecycleState = await handle.session.state
            } else if package.validationError != nil {
                lifecycleState = .failedValidation
            } else if hostState.quarantined {
                lifecycleState = .terminated
            } else {
                lifecycleState = .discovered
            }
            result.append(SDKManagedExtension(
                id: package.id,
                name: package.manifest?.name ?? package.id,
                version: package.manifest?.version ?? "—",
                installPath: package.installPath.path,
                packageDigest: package.digest ?? "—",
                manifest: package.manifest,
                enabled: hostState.enabled,
                lifecycleState: lifecycleState,
                crashCount: crashCounts[package.id] ?? 0,
                quarantined: hostState.quarantined,
                diagnostic: diagnostics[package.id]
                    ?? package.validationError.map { userDiagnostic(for: $0) }
                    ?? hostState.quarantineReason
            ))
        }
        return result.sorted { $0.id < $1.id }
    }

    private func userDiagnostic(for error: SDKError) -> String {
        var text = error.message
        if let suggestion = error.suggestion, !suggestion.isEmpty {
            text += " " + suggestion
        }
        return text
    }

    // MARK: - Startup (SDKBootstrap entry point)

    /// Starts every enabled, valid extension. Called once from
    /// `SDKBootstrap.bootstrapIfNeeded()`. Never throws: per-extension
    /// failures are logged, diagnosed to the user, and recorded in the
    /// returned summary — one broken extension can never prevent the rest
    /// from starting.
    public func startAll() async -> SDKExtensionLaunchSummary {
        var started: [String] = []
        var skipped: [(id: String, reason: String)] = []
        var failed: [(id: String, reason: String)] = []

        let packages: [DiscoveredPackage]
        do {
            packages = try await discover()
        } catch {
            let reason = (error as? SDKError)?.message ?? error.localizedDescription
            Self.log.error("SDKExtensionManager.startAll: discovery failed: \(reason, privacy: .public)")
            return SDKExtensionLaunchSummary(started: [], skipped: [], failed: [])
        }

        for package in packages {
            let hostState = state(for: package.id)
            if let validationError = package.validationError {
                let reason = userDiagnostic(for: validationError)
                diagnostics[package.id] = reason
                await SDKUserLogger.shared.log(validationError)
                await SDKAuditLog.shared.record(
                    type: .runtimeTerminated,
                    extensionID: package.id,
                    detail: "invalid package stayed stopped: \(validationError.code.rawValue)"
                )
                skipped.append((id: package.id, reason: reason))
                continue
            }
            guard hostState.enabled else {
                skipped.append((id: package.id, reason: "Disabled — enable it in Studio to start it."))
                continue
            }
            guard !hostState.quarantined else {
                skipped.append((id: package.id, reason: hostState.quarantineReason ?? "Quarantined."))
                continue
            }
            guard package.manifest != nil else {
                skipped.append((id: package.id, reason: "No valid manifest."))
                continue
            }
            do {
                try await launchValidated(package: package)
                started.append(package.id)
            } catch {
                let reason = (error as? SDKError).map(userDiagnostic) ?? error.localizedDescription
                diagnostics[package.id] = reason
                failed.append((id: package.id, reason: reason))
            }
        }
        return SDKExtensionLaunchSummary(started: started, skipped: skipped, failed: failed)
    }

    // MARK: - Launch

    /// Launches one discovered extension by ID. Throws a typed `SDKError`
    /// on every failure path — never a fake "started".
    public func launch(extensionID: String) async throws {
        guard handles[extensionID] == nil else {
            throw SDKError(
                code: .invalidArgument,
                message: "“\(extensionID)” is already running.",
                suggestion: "Stop it before launching it again."
            )
        }
        let packages = try await discover()
        guard let package = packages.first(where: { $0.id == extensionID }) else {
            throw SDKError(
                code: .invalidArgument,
                message: "“\(extensionID)” is not installed.",
                suggestion: "Install the extension into ~/.swiftcode/extensions first."
            )
        }
        if let validationError = package.validationError {
            diagnostics[extensionID] = userDiagnostic(for: validationError)
            throw validationError
        }
        let hostState = state(for: extensionID)
        guard hostState.enabled else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "“\(extensionID)” is disabled.",
                suggestion: "Enable it in Studio → Extensions before launching."
            )
        }
        guard !hostState.quarantined else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "“\(extensionID)” is quarantined: \(hostState.quarantineReason ?? "repeated crashes").",
                suggestion: "Fix the underlying problem, then re-enable the extension in Studio to clear the quarantine."
            )
        }
        guard package.manifest != nil else {
            throw SDKError(
                code: .manifestInvalid,
                message: "“\(extensionID)” has no valid manifest.",
                suggestion: "Reinstall the extension."
            )
        }
        try await launchValidated(package: package)
    }

    /// Launch path for an already-discovered, already-validated package.
    private func launchValidated(package: DiscoveredPackage) async throws {
        let id = package.id
        guard let manifest = package.manifest else {
            throw SDKError(
                code: .manifestInvalid,
                message: "“\(id)” has no valid manifest.",
                suggestion: "Reinstall the extension."
            )
        }

        // Tamper check (spec §8.7): a digest change since the last clean
        // scan revokes grants and quarantines the package — the install
        // record is not trusted over the bytes on disk.
        if let digest = package.digest {
            var hostState = state(for: id)
            if let recorded = hostState.recordedDigest, recorded != digest {
                let revocationNote: String
                do {
                    try await SDKGrantStore.shared.revokeAll(for: id)
                    revocationNote = "Its capability grants were revoked as a precaution."
                } catch {
                    // Never claim a revocation that did not happen.
                    revocationNote = "Revoking its capability grants FAILED (\(String(describing: error))); treat all of its grants as untrusted until it is reinstalled."
                }
                hostState.quarantined = true
                hostState.quarantineReason =
                    "The installed package changed on disk since it was last scanned. "
                    + revocationNote
                setState(hostState, for: id)
                await SDKAuditLog.shared.record(
                    type: .permissionRevoked,
                    extensionID: id,
                    detail: "package digest changed on disk; grants revoked, extension quarantined"
                )
                let message = hostState.quarantineReason ?? "Package changed on disk."
                diagnostics[id] = message
                await SDKUserLogger.shared.logWarning(
                    "“\(manifest.name)” was quarantined: \(message)",
                    correlationId: nil
                )
                throw SDKError(
                    code: .packageIntegrityFailure,
                    message: message,
                    suggestion: "Reinstall the extension to re-approve it."
                )
            }
            if hostState.recordedDigest == nil {
                hostState.recordedDigest = digest
                setState(hostState, for: id)
            }
        }

        let adapterURL = try resolveAdapterURL()

        let info = SDKRuntimeSessionInfo(
            extensionID: id,
            packageDigest: package.digest ?? "",
            projectRootPath: package.installPath.path,
            manifest: manifest,
            presentedAPIKey: SDKAPIKeySessionAuth.presentedKeyFromEnvironment()
        )
        let session = SDKRuntimeSession(info: info)
        try await session.transition(to: .validated)
        // v1 has no launch-time consent gate beyond the user's enabled
        // toggle and the per-capability approval UI: the extension runs
        // with no granted capabilities until the user approves each one.
        try await session.transition(to: .awaitingPermission)
        try await session.transition(to: .ready)

        // Teardown hook: the owner (this manager) disposes extension-owned
        // resources — contributed commands first, per spec §10.5.
        await session.setOnDeactivate { [extensionID = id] in
            await SDKCommandRegistry.shared.unregisterAll(extensionID: extensionID)
        }

        let entrypointURL = package.installPath
            .appendingPathComponent(manifest.runtime.entrypoint)
        let manifestURL = package.installPath
            .appendingPathComponent(Self.manifestFileName)

        let launched: SDKLaunchedRuntime
        do {
            launched = try SDKNodeLauncher.launch(
                entrypoint: adapterURL,
                workingDirectory: package.installPath,
                arguments: [
                    "--entrypoint", entrypointURL.path,
                    "--manifest", manifestURL.path,
                    "--id", id,
                    "--version", manifest.version,
                    "--name", manifest.name,
                ]
            )
        } catch {
            try? await session.transition(to: .launchFailed)
            await reportLaunchFailure(id: id, name: manifest.name, error: error)
            throw error
        }
        try await session.transition(to: .starting)

        let transport = SDKIPCTransport(
            stdin: launched.stdinPipe,
            stdout: launched.stdoutPipe
        )
        let dispatcher = SDKIPCDispatcher(
            session: info,
            send: { [transport] data in
                // The dispatcher contract is non-throwing: a broken pipe
                // means the runtime is dying; the termination watcher owns
                // restart accounting, but the failure is still logged.
                do {
                    try await transport.sendMessage(data)
                } catch {
                    let sendError = SDKError(
                        code: .runtimeCrash,
                        message: "Lost the IPC channel to the extension runtime.",
                        suggestion: "The runtime is terminating; its supervisor will handle the restart.",
                        diagnostics: ["underlyingError": String(describing: error)]
                    )
                    await SDKDeveloperLogger.shared.log(sendError)
                }
            }
        )

        // Register the handle BEFORE starting the pumps so the event and
        // termination handlers can find it.
        handles[id] = RuntimeHandle(
            session: session,
            launched: launched,
            transport: transport,
            dispatcher: dispatcher,
            ioTask: Task { },
            terminationTask: Task { }
        )
        handles[id]?.ioTask = Task { [weak self] in
            await self?.pumpIO(extensionID: id)
        }
        handles[id]?.terminationTask = Task { [weak self] in
            let status = await launched.waitForExit()
            await self?.handleTermination(extensionID: id, exitCode: status)
        }

        // Activation handshake: the adapter emits `extension.ready` after
        // `activate()` succeeds, or `extension.activationFailed` (then it
        // exits). Bounded by the activation budget.
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                activationWaiters[id] = continuation
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: Self.activationTimeoutNanoseconds)
                    await self?.failActivation(
                        id,
                        error: SDKError(
                            code: .activationTimeout,
                            message: "“\(manifest.name)” did not report ready within 30 seconds.",
                            suggestion: "Check the extension's activate() implementation for hangs, then try again."
                        )
                    )
                }
            }
        } catch {
            // Activation failed or timed out: tear down everything we
            // started, so no half-launched runtime lingers.
            await teardownHandle(id: id, terminateProcess: true)
            throw error
        }
    }

    /// Resolves the node runtime adapter (`adapter.js`) the host spawns per
    /// extension. Resolution order:
    ///   1. `SWIFTCODE_SDK_ADAPTER_PATH` — explicit override (tilde
    ///      expanded); must name an existing file.
    ///   2. `adapter.js` bundled in the app resources (the future
    ///      packaging step — see SDKStudioExtensionsView's CLI notes for
    ///      the same reachability reasoning).
    ///
    /// When neither resolves, launching fails with a typed
    /// `.runtimeUnavailable` error carrying actionable guidance — never a
    /// silent skip or a fake launch.
    private func resolveAdapterURL() throws -> URL {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["SWIFTCODE_SDK_ADAPTER_PATH"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                throw SDKError(
                    code: .runtimeUnavailable,
                    message: "SWIFTCODE_SDK_ADAPTER_PATH points to '\(override)', which is not a file.",
                    suggestion: "Point SWIFTCODE_SDK_ADAPTER_PATH at the SDK runtime adapter (SwiftCode/SDK/TypeScript/runtime-adapter/dist/adapter.js in a SwiftCode-Mac checkout)."
                )
            }
            return URL(fileURLWithPath: expanded)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("SwiftCodeSDK/TypeScript/runtime-adapter/dist/adapter.js"),
           fileManager.fileExists(atPath: bundled.path) {
            return bundled
        }
        throw SDKError(
            code: .runtimeUnavailable,
            message: "The SwiftCode SDK runtime adapter (adapter.js) was not found.",
            suggestion: "Set SWIFTCODE_SDK_ADAPTER_PATH to SwiftCode/SDK/TypeScript/runtime-adapter/dist/adapter.js in a SwiftCode-Mac checkout, or install a SwiftCode build that bundles the adapter."
        )
    }

    private func reportLaunchFailure(id: String, name: String, error: Error) async {
        let reason: String
        if let sdkError = error as? SDKError {
            reason = userDiagnostic(for: sdkError)
            await SDKUserLogger.shared.log(sdkError)
            await SDKDeveloperLogger.shared.log(
                sdkError,
                context: ["extensionID": id]
            )
        } else {
            reason = error.localizedDescription
            await SDKUserLogger.shared.log(
                error: error,
                title: "“\(name)” failed to start"
            )
        }
        diagnostics[id] = reason
        await SDKAuditLog.shared.record(
            type: .runtimeTerminated,
            extensionID: id,
            detail: "launch failed: \((error as? SDKError)?.code.rawValue ?? "unknown")"
        )
    }

    // MARK: - Activation handshake

    private func completeActivation(_ id: String, result: Result<Void, Error>) {
        guard let waiter = activationWaiters.removeValue(forKey: id) else { return }
        switch result {
        case .success: waiter.resume()
        case .failure(let error): waiter.resume(throwing: error)
        }
    }

    private func failActivation(_ id: String, error: Error) {
        completeActivation(id, result: .failure(error))
    }

    // MARK: - IPC pump

    /// Reads frames from one runtime's stdout for the life of the process:
    /// extension→host requests are dispatched (responses written back),
    /// host→extension events (`extension.ready`, `commands.executeResult`,
    /// …) are handled. Any framing/transport failure ends the loop — the
    /// termination watcher owns crash accounting and restarts.
    private func pumpIO(extensionID id: String) async {
        guard let handle = handles[id] else { return }
        let transport = handle.transport
        let dispatcher = handle.dispatcher
        while true {
            do {
                let frame = try await transport.readMessage()
                let type = try SDKIPCCodec.decodeEnvelopeType(from: frame)
                switch type {
                case .request:
                    let response = await dispatcher.dispatch(frame)
                    do {
                        try await transport.sendMessage(response)
                    } catch {
                        return // broken pipe — termination watcher takes over
                    }
                case .event:
                    await handleRuntimeEvent(frame, extensionID: id)
                case .response:
                    // The host never issues requests to the runtime; an
                    // inbound response frame is a protocol violation.
                    // Logged, never fatal.
                    await SDKDeveloperLogger.shared.log(
                        SDKError(
                            code: .ipcMalformed,
                            message: "Unexpected response frame from the extension runtime.",
                            suggestion: "The extension sent a frame the host never requested; it was ignored.",
                            diagnostics: ["extensionID": id]
                        )
                    )
                }
            } catch {
                return
            }
            // Re-fetch the handle each lap: teardown replaces `handles[id]`.
            guard handles[id] != nil, !Task.isCancelled else { return }
        }
    }

    /// Handles one host→extension event frame from a runtime.
    private func handleRuntimeEvent(_ frame: Data, extensionID id: String) async {
        let envelope: SDKEventEnvelope<SDKJSONValue>
        do {
            envelope = try JSONDecoder().decode(SDKEventEnvelope<SDKJSONValue>.self, from: frame)
        } catch {
            await SDKDeveloperLogger.shared.log(
                SDKError(
                    code: .ipcMalformed,
                    message: "Malformed event frame from the extension runtime.",
                    suggestion: "The frame was ignored.",
                    diagnostics: ["extensionID": id, "underlyingError": String(describing: error)]
                )
            )
            return
        }
        switch envelope.event {
        case "extension.ready":
            await handleExtensionReady(envelope, extensionID: id)
        case "extension.activationFailed":
            await handleActivationFailed(envelope, extensionID: id)
        case "extension.error":
            if case .object(let fields) = envelope.payload,
               case .string(let message) = fields["message"] {
                await SDKDeveloperLogger.shared.log(
                    SDKError(
                        code: .runtimeCrash,
                        message: "Extension runtime reported an error.",
                        diagnostics: ["extensionID": id, "runtimeMessage": message]
                    )
                )
            }
        case "commands.executeResult":
            completeCommandResult(envelope, extensionID: id)
        default:
            // Forward-compatible: unknown events are logged, never fatal.
            Self.log.debug("SDKExtensionManager: ignoring unknown runtime event '\(envelope.event, privacy: .public)' from \(id, privacy: .public)")
        }
    }

    private func handleExtensionReady(
        _ envelope: SDKEventEnvelope<SDKJSONValue>,
        extensionID id: String
    ) async {
        guard let handle = handles[id] else { return }
        if case .object(let fields) = envelope.payload,
           case .int(let protocolVersion) = fields["protocolVersion"],
           protocolVersion != SDKIPCCodec.sdkProtocolVersion {
            try? await handle.session.transition(to: .activationFailed)
            let error = SDKError(
                code: .ipcProtocolMismatch,
                message: "“\(id)” speaks IPC protocol version \(protocolVersion); this host speaks version \(SDKIPCCodec.sdkProtocolVersion).",
                suggestion: "Update the extension to a matching @swiftcode/sdk release."
            )
            await SDKUserLogger.shared.log(error)
            completeActivation(id, result: .failure(error))
            await teardownHandle(id: id, terminateProcess: true)
            return
        }
        try? await handle.session.transition(to: .active)
        completeActivation(id, result: .success(()))
        Self.log.debug("SDKExtensionManager: '\(id, privacy: .public)' active")
    }

    private func handleActivationFailed(
        _ envelope: SDKEventEnvelope<SDKJSONValue>,
        extensionID id: String
    ) async {
        guard let handle = handles[id] else { return }
        var message = "The extension's activate() threw an error."
        if case .object(let fields) = envelope.payload,
           case .string(let runtimeMessage) = fields["message"],
           !runtimeMessage.isEmpty {
            message = runtimeMessage
        }
        try? await handle.session.transition(to: .activationFailed)
        let error = SDKError(
            code: .activationFailed,
            message: "“\(id)” failed to activate: \(message)",
            suggestion: "Fix the extension's activate() implementation and try again.",
            diagnostics: ["extensionID": id]
        )
        diagnostics[id] = userDiagnostic(for: error)
        await SDKUserLogger.shared.log(error)
        await SDKDeveloperLogger.shared.log(error, context: ["extensionID": id])
        completeActivation(id, result: .failure(error))
        // The adapter exits on its own after reporting activation failure;
        // the termination watcher will observe the exit.
    }

    // MARK: - Command invocation (context.commands path)

    /// Invokes one of the extension's contributed commands. The call goes
    /// through the TS runtime — a `commands.execute` host event dispatched
    /// to the handler the extension registered via `context.commands` —
    /// never native injection. The extension's `commands.executeResult`
    /// event completes the call, bounded by the command timeout.
    ///
    /// - Throws: `.serviceUnavailable` when the extension is not active,
    ///   `.invalidArgument` for an unknown command ID, `.ipcTimeout` when
    ///   the runtime does not answer in time, or the extension's own error
    ///   projected as a typed `SDKError`.
    public func invokeCommand(extensionID id: String, commandID: String) async throws -> SDKJSONValue {
        guard let handle = handles[id] else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "“\(id)” is not running.",
                suggestion: "Launch the extension before invoking its commands."
            )
        }
        guard await handle.session.state == .active else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "“\(id)” is not active.",
                suggestion: "Wait for the extension to finish starting, then try again."
            )
        }
        // Only declared or runtime-registered commands may be invoked —
        // the host never invents a command ID for the extension.
        let declared = (try? await discover().first(where: { $0.id == id })?.manifest?.contributes?.commands.map(\.id)) ?? []
        let registered = await SDKCommandRegistry.shared.commands(for: id).map(\.id)
        let known = Set(declared).union(registered)
        guard known.contains(commandID) else {
            throw SDKError(
                code: .invalidArgument,
                message: "“\(id)” has no command “\(commandID)”.",
                suggestion: known.isEmpty
                    ? "The extension contributes no commands."
                    : "Available commands: \(known.sorted().joined(separator: ", "))."
            )
        }

        let invocationID = UUID().uuidString
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SDKJSONValue, Error>) in
            pendingInvocations[invocationID] = (extensionID: id, continuation: continuation)
            let dispatcher = handle.dispatcher
            Task { [weak self] in
                await dispatcher.event(
                    "commands.execute",
                    payload: .object([
                        "commandId": .string(commandID),
                        "invocationId": .string(invocationID),
                        "payload": .object([:]),
                    ]),
                    requestId: invocationID
                )
                // Arm the timeout only after the event is on the wire.
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: Self.commandTimeoutNanoseconds)
                    await self?.failInvocation(
                        invocationID,
                        error: SDKError(
                            code: .ipcTimeout,
                            message: "“\(id)” did not answer the “\(commandID)” command within 60 seconds.",
                            suggestion: "The extension may be busy or hung; check its logs."
                        )
                    )
                }
            }
        }
    }

    /// Completes a pending `commands.execute` invocation from the runtime's
    /// `commands.executeResult` event. Exactly-once: the waiter is removed
    /// before resuming, so a late duplicate (or the timeout) is a no-op.
    private func completeCommandResult(
        _ envelope: SDKEventEnvelope<SDKJSONValue>,
        extensionID id: String
    ) {
        guard case .object(let fields) = envelope.payload,
              case .string(let invocationID) = fields["invocationId"],
              let pending = pendingInvocations.removeValue(forKey: invocationID),
              pending.extensionID == id else {
            return
        }
        let continuation = pending.continuation
        let ok: Bool = {
            if case .bool(let value) = fields["ok"] { return value }
            return false
        }()
        if ok {
            continuation.resume(returning: fields["result"] ?? .null)
        } else {
            var message = "The extension command failed."
            var code = "COMMAND_FAILED"
            if case .object(let errorFields) = fields["error"] {
                if case .string(let value) = errorFields["message"], !value.isEmpty {
                    message = value
                }
                if case .string(let value) = errorFields["code"], !value.isEmpty {
                    code = value
                }
            }
            let sdkCode: SDKErrorCode = code == "UNKNOWN_COMMAND" ? .invalidArgument : .serviceUnavailable
            continuation.resume(throwing: SDKError(
                code: sdkCode,
                message: "“\(id)” command failed: \(message)",
                suggestion: "Check the extension's logs for details.",
                diagnostics: ["extensionID": id, "extensionErrorCode": code]
            ))
        }
    }

    private func failInvocation(_ invocationID: String, error: Error) {
        guard let pending = pendingInvocations.removeValue(forKey: invocationID) else { return }
        pending.continuation.resume(throwing: error)
    }

    // MARK: - Termination / crash handling

    /// Observes one runtime's exit. Expected exits (intentional stop /
    /// uninstall removed the handle first) are ignored. Unexpected exits
    /// are crash-accounted: bounded restarts with exponential backoff, then
    /// quarantine — never an infinite crash/restart loop.
    private func handleTermination(extensionID id: String, exitCode: Int32) async {
        guard let handle = handles[id] else { return } // intentional stop
        let sessionState = await handle.session.state
        switch sessionState {
        case .stopping, .stopped:
            // Graceful stop completed; finish the teardown.
            await teardownHandle(id: id, terminateProcess: false)
            return
        default:
            break // unexpected — crash path below
        }

        await handle.session.markCrashed(exitCode: exitCode)
        let total = (crashCounts[id] ?? 0) + 1
        crashCounts[id] = total

        // The old IO pump is done: its transport is closed below, so its
        // next read fails and it exits. Cancel it explicitly as well so a
        // relaunch never shares a pump with a dead runtime.
        handle.ioTask.cancel()

        // Clean up contributions immediately: a dead extension leaves no
        // stale commands behind (spec §10.5).
        await SDKCommandRegistry.shared.unregisterAll(extensionID: id)
        await handle.transport.close()

        let history = await handle.session.stateHistory
            .map { "\($0.state.rawValue)" }.joined(separator: "→")
        let crashError = SDKError(
            code: .runtimeCrash,
            message: "“\(id)” crashed (exit code \(exitCode)) — crash #\(total) of \(SDKRuntimeSession.maxCrashRestarts) allowed.",
            suggestion: total < SDKRuntimeSession.maxCrashRestarts
                ? "SwiftCode will retry starting it with a backoff delay."
                : "It has been quarantined and will not restart until you re-enable it.",
            diagnostics: ["extensionID": id, "exitCode": "\(exitCode)", "history": history]
        )
        await SDKDeveloperLogger.shared.log(crashError, context: ["extensionID": id])
        // markCrashed already audit-recorded `.runtimeTerminated`.

        // Remove the dead handle before any restart so the new launch
        // starts from a clean slate (and so a concurrent intentional stop
        // cannot race the restart).
        handles.removeValue(forKey: id)

        if total < SDKRuntimeSession.maxCrashRestarts {
            let delaySeconds = min(
                UInt64(1) << UInt64(total), // 2, 4, 8, …
                Self.maxRestartBackoffSeconds
            )
            Self.log.debug("SDKExtensionManager: '\(id, privacy: .public)' crashed; retrying in \(delaySeconds, privacy: .public)s")
            await SDKUserLogger.shared.logWarning(
                "“\(id)” crashed and will be retried in \(delaySeconds)s (crash #\(total) of \(SDKRuntimeSession.maxCrashRestarts)).",
                correlationId: crashError.correlationId
            )
            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            // The user may have disabled or uninstalled it during the
            // backoff — re-check before relaunching.
            let hostState = state(for: id)
            guard hostState.enabled, !hostState.quarantined else { return }
            do {
                let packages = try await discover()
                if let package = packages.first(where: { $0.id == id }),
                   package.validationError == nil {
                    try await launchValidated(package: package)
                }
            } catch {
                let reason = (error as? SDKError).map(userDiagnostic) ?? error.localizedDescription
                diagnostics[id] = reason
                await SDKUserLogger.shared.logWarning(
                    "“\(id)” could not be restarted: \(reason)",
                    correlationId: nil
                )
            }
        } else {
            await quarantine(id: id, reason:
                "It crashed \(total) times and was quarantined to protect stability. "
                + "Last exit code: \(exitCode)."
            )
        }
    }

    /// Quarantines an extension: it stays stopped until the user re-enables
    /// it (which clears the quarantine) or reinstalls it. Contributions are
    /// removed and the quarantine is persisted across launches.
    private func quarantine(id: String, reason: String) async {
        var hostState = state(for: id)
        hostState.quarantined = true
        hostState.quarantineReason = reason
        setState(hostState, for: id)
        diagnostics[id] = reason
        await teardownHandle(id: id, terminateProcess: true)
        await SDKUserLogger.shared.logWarning(
            "“\(id)” was quarantined: \(reason)",
            correlationId: nil
        )
        await SDKAuditLog.shared.record(
            type: .extensionDisabled,
            extensionID: id,
            detail: "quarantined: \(reason)"
        )
        Self.log.error("SDKExtensionManager: quarantined '\(id, privacy: .public)': \(reason, privacy: .public)")
    }

    /// Clears a quarantine (user action via re-enable). The crash budget is
    /// reset too: the user inspected the problem and asked for another
    /// chance, so the extension gets a fresh retry budget.
    private func clearQuarantine(id: String) {
        var hostState = state(for: id)
        guard hostState.quarantined else { return }
        hostState.quarantined = false
        hostState.quarantineReason = nil
        setState(hostState, for: id)
        diagnostics.removeValue(forKey: id)
        crashCounts.removeValue(forKey: id)
    }

    // MARK: - Stop / teardown

    /// Tears down one runtime: cancels the pumps, runs the session's
    /// ordered deactivation (commands disposed via the `onDeactivate`
    /// hook), terminates the process, and removes the handle. Bounded:
    /// deactivation is raced against the stop budget.
    private func teardownHandle(id: String, terminateProcess: Bool) async {
        guard let handle = handles.removeValue(forKey: id) else { return }
        handle.ioTask.cancel()
        handle.terminationTask.cancel()
        // Fail any waiters tied to THIS runtime so callers never hang.
        // (Other extensions' invocations are untouched.) Keys are collected
        // first: removing during iteration would trap.
        let doomedInvocations = pendingInvocations
            .filter { $0.value.extensionID == id }
            .map(\.key)
        for invocationID in doomedInvocations {
            if let pending = pendingInvocations.removeValue(forKey: invocationID) {
                pending.continuation.resume(throwing: SDKError(
                    code: .serviceUnavailable,
                    message: "“\(id)” stopped while the command was running.",
                    suggestion: "Relaunch the extension and try again."
                ))
            }
        }
        if let waiter = activationWaiters.removeValue(forKey: id) {
            waiter.resume(throwing: SDKError(
                code: .serviceUnavailable,
                message: "“\(id)” stopped during activation.",
                suggestion: "Try launching it again."
            ))
        }
        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await handle.session.deactivate()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.stopTimeoutNanoseconds)
            }
            // First finished wins; the group is cancelled on exit.
            _ = try? await group.next()
            group.cancelAll()
        }
        if terminateProcess {
            await handle.launched.terminate()
        }
        await handle.transport.close()
    }

    /// Gracefully stops one extension if it is running.
    public func stop(extensionID id: String) async {
        await teardownHandle(id: id, terminateProcess: true)
    }

    /// Gracefully stops every running extension. Bounded per extension.
    public func stopAll() async {
        for id in Array(handles.keys) {
            await teardownHandle(id: id, terminateProcess: true)
        }
    }

    // MARK: - Enable / disable

    /// Flips the enabled flag. Disabling stops a running extension;
    /// enabling launches it and clears any quarantine. Throws a typed
    /// `SDKError` when enabling fails to launch.
    public func setEnabled(_ enabled: Bool, extensionID id: String) async throws {
        var hostState = state(for: id)
        hostState.enabled = enabled
        if enabled {
            clearQuarantine(id: id)
        }
        setState(hostState, for: id)
        if enabled {
            await SDKAuditLog.shared.record(
                type: .permissionGranted,
                extensionID: id,
                detail: "extension enabled by user"
            )
            try await launch(extensionID: id)
        } else {
            await stop(extensionID: id)
            await SDKAuditLog.shared.record(
                type: .extensionDisabled,
                extensionID: id,
                detail: "extension disabled by user"
            )
        }
    }

    // MARK: - Uninstall

    /// Fully uninstalls an extension:
    ///   1. stops the runtime (bounded),
    ///   2. removes contributed commands,
    ///   3. revokes every capability grant (spec §8.7 — grants die with the
    ///      extension),
    ///   3b. revokes the app's Assist entitlement bindings and closes its
    ///      open Assist sessions (Docs/Intro-to-SDK.md §14),
    ///   4. wipes the extension's Security namespace values,
    ///   5. deletes the installed package directory from disk,
    ///   6. drops host state.
    /// Audit-recorded. Throws `.uninstallFailed` with an actionable message
    /// on any failure — nothing is faked as removed.
    public func uninstall(extensionID id: String) async throws {
        let packages = try? await discover()
        let installPath = packages?.first(where: { $0.id == id })?.installPath

        await stop(extensionID: id)
        await SDKCommandRegistry.shared.unregisterAll(extensionID: id)

        do {
            try await SDKGrantStore.shared.revokeAll(for: id)
        } catch {
            throw SDKError(
                code: .uninstallFailed,
                message: "Could not revoke “\(id)”’s capability grants.",
                suggestion: "Try again; the extension was left installed so no grant survives silently.",
                diagnostics: ["underlyingError": String(describing: error)]
            )
        }

        // Docs/Intro-to-SDK.md §14: uninstalling the app removes its
        // Assist entitlement bindings. Each revocation goes through
        // `SDKAPIKeyStore.revokeEntitlement` (immediate at the
        // authorization boundary, in-flight Assist sessions closed,
        // audit-recorded); the app's own open Assist sessions are closed
        // too. A failure here must not leave the extension installed with
        // dead bindings half-removed: `revokeEntitlementsForExtension`
        // never throws, so the uninstall continues.
        let revokedEntitlements = await SDKAssistApplicationStore.shared.revokeEntitlementsForExtension(id)
        let closedAssistSessions = await SDKAssistService.shared.closeSessions(forExtensionID: id)

        do {
            let wiped = try await SDKSecurityService.shared.deleteAllValues(securityID: id)
            await SDKAuditLog.shared.record(
                type: .securityValuesWipedOnUninstall,
                extensionID: id,
                detail: "wiped \(wiped) security value(s) on uninstall"
            )
        } catch {
            throw SDKError(
                code: .uninstallFailed,
                message: "Could not wipe “\(id)”’s stored secrets.",
                suggestion: "Secrets must never silently survive an uninstall — the extension was left installed. Try again.",
                diagnostics: ["underlyingError": String(describing: error)]
            )
        }

        if let installPath {
            do {
                try FileManager.default.removeItem(at: installPath)
            } catch {
                throw SDKError(
                    code: .uninstallFailed,
                    message: "Could not remove “\(id)”’s installed files.",
                    suggestion: "Check the permissions of ~/.swiftcode/extensions and try again.",
                    diagnostics: ["underlyingError": String(describing: error)]
                )
            }
        }

        loadPersistedState()
        persistedState.removeValue(forKey: id)
        savePersistedState()
        diagnostics.removeValue(forKey: id)
        crashCounts.removeValue(forKey: id)

        await SDKAuditLog.shared.record(
            type: .extensionUninstalled,
            extensionID: id,
            detail: "uninstalled; commands removed, grants revoked, security values wiped, assist entitlements revoked (\(revokedEntitlements)), assist sessions closed (\(closedAssistSessions))"
        )
        Self.log.debug("SDKExtensionManager: uninstalled '\(id, privacy: .public)'")
    }
}

// MARK: - SDKRuntimeSession onDeactivate setter
//
// `onDeactivate` is actor-isolated on `SDKRuntimeSession`; the manager (a
// different actor) needs a way to install it. This tiny extension is the
// sanctioned path.

private extension SDKRuntimeSession {
    func setOnDeactivate(_ hook: (@Sendable () async -> Void)?) {
        self.onDeactivate = hook
    }
}
