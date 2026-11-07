#if canImport(AppKit)
import AppKit
#endif
import Foundation
import SwiftCodeAssistant

@MainActor
public final class CodingAssistantServices {
    public static var shared = CodingAssistantServices()

    public var store: SecretStore
    public let account: OpenAIAccount
    public var providerOverride: ((ProviderKind) -> AssistantProvider?)?
    public var locator = CLIToolLocator()
    public var preferences: Preferences?

    public init(store: SecretStore? = nil, openURL: (@Sendable (URL) -> Bool)? = nil) {
        let s = store ?? (IDEProcess.isTestProcess ? MemorySecretStore() : defaultSecretStore())
        self.store = s
        #if canImport(Security)
        let verifier: IDTokenSignatureVerifier? = JWKSSignatureVerifier()
        #else
        let verifier: IDTokenSignatureVerifier? = nil
        #endif
        account = OpenAIAccount(store: s, verifier: verifier, openURL: openURL ?? Self.openInBrowser)
    }

    public static let openInBrowser: @Sendable (URL) -> Bool = { url in
        #if canImport(AppKit)
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        return true
        #else
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["xdg-open", url.absoluteString]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        return true
        #endif
    }

    public func backends(_ prefs: Preferences = .shared) -> AssistantBackends {
        AssistantBackends(settings: prefs.codingAssistant, store: store, account: account, locator: locator)
    }

    public func provider(_ kind: ProviderKind, prefs: Preferences = .shared) -> AssistantProvider {
        providerOverride?(kind) ?? backends(prefs).provider(kind)
    }

    public func survey(prefs: Preferences = .shared) async -> [ProviderKind: ProviderAvailability] {
        let kinds = ProviderKind.allCases
        let providers = kinds.map { provider($0, prefs: prefs) }
        return await withTaskGroup(of: (ProviderKind, ProviderAvailability).self) { group in
            for (k, p) in zip(kinds, providers) { group.addTask { (k, await p.availability()) } }
            var out: [ProviderKind: ProviderAvailability] = [:]
            for await (k, a) in group { out[k] = a }
            return out
        }
    }
}
