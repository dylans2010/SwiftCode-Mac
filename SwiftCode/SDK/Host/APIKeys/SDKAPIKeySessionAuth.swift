import Foundation

// MARK: - SDKAPIKeySessionAuth
//
// The DELIVERY CONVENTION for developer API keys (spec §8.2.1, ADR §11):
// how a secret travels from its one-time reveal in Studio to the host
// session that presents it — without ever being persisted by the host.
//
// The full journey of a secret:
//   1. Studio → Settings → Developer API Keys → Generate. The secret is
//      displayed EXACTLY ONCE and cleared from memory on Done/dismiss.
//      It is never logged, never persisted, never embedded in an error.
//   2. The developer copies it into the environment of the process that
//      hosts their extension session:
//          export SWIFTCODE_API_KEY='sc_dev_live_…'
//      (shell profile, CI secret store, or the `swiftcode dev` invocation —
//      wherever the HOST process's environment is composed).
//   3. When the host coordinator creates the extension's
//      `SDKRuntimeSessionInfo`, it calls
//      `SDKAPIKeySessionAuth.presentedKeyFromEnvironment()` and stores the
//      result in `SDKRuntimeSessionInfo.presentedAPIKey`. Session info is
//      in-memory only; the secret is never written to disk by the host.
//   4. `SDKIPCDispatcher` verifies the presented secret against
//      `SDKAPIKeyStore` on every request the session makes (fail closed
//      with a typed error). Revocation and expiry therefore take effect on
//      the very next request — no "still valid" verdict is ever cached.
//   5. If the secret is lost, there is no recovery: revoke the key in
//      Studio and generate a new one (rotation = revoke + create, recorded
//      as an `apiKeyRevoked` + `apiKeyCreated` audit pair).
//
// WHY AN ENVIRONMENT VARIABLE
// - It is ephemeral (process memory only), the standard convention for
//   developer secrets (cf. `OPENAI_API_KEY`), and it keeps the secret out
//   of the extension process entirely: the EXTENSION never sees the key —
//   only the host binds it to the session. No wire-protocol change, no
//   secret in IPC frames, no secret in extension logs.
// - A file-based config store is deliberately NOT provided: a plaintext
//   key file on disk is a persistence the host cannot protect, and secrets
//   may not be stored anywhere except the Keychain path (which holds key
//   METADATA and the device key — never secrets).
//
// SECURITY CONTRACT: every `String` returned here is toxic — never log it,
// never interpolate it into errors or diagnostics, never persist it.

public enum SDKAPIKeySessionAuth {

    /// The environment variable the host coordinator reads when creating
    /// an extension session (see `SDKRuntimeSessionInfo.presentedAPIKey`).
    public static let environmentVariableName = "SWIFTCODE_API_KEY"

    /// Returns the developer API key secret the host should bind to a new
    /// extension session, or nil when the variable is unset or blank (the
    /// session then authorizes purely through user grants — today's
    /// behavior).
    ///
    /// `environment` is injectable for tests; production passes the real
    /// process environment.
    ///
    /// The returned string is toxic (see the contract above): hand it to
    /// `SDKRuntimeSessionInfo.presentedAPIKey` and nowhere else.
    public static func presentedKeyFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let raw = environment[environmentVariableName] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
