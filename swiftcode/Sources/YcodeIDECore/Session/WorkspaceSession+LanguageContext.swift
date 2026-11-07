import Foundation
import YcodeBuild
import YcodeDebug
import YcodeLanguage

public struct LanguageBuildContext: Equatable, Sendable {
    public var scheme: String?
    public var destination: String?
    public init(scheme: String?, destination: String?) {
        self.scheme = scheme
        self.destination = destination
    }
}

@MainActor
final class LanguageRestartState {
    var context: LanguageBuildContext?
    var pending: Task<Void, Never>?
    var makeTransport: (() -> DAPTransport)?
    var count = 0
}

extension WorkspaceSession {
    public var languageBuildContext: LanguageBuildContext {
        LanguageBuildContext(scheme: scheme, destination: destination?.specifier)
    }

    public var languageServedContext: LanguageBuildContext? { languageRestart.context }

    public var languageRestartCount: Int { languageRestart.count }

    public var languageTransportFactory: (() -> DAPTransport)? {
        get { languageRestart.makeTransport }
        set { languageRestart.makeTransport = newValue }
    }

    func buildContextChanged() {
        guard language != nil, let served = languageRestart.context, served != languageBuildContext else { return }
        languageRestart.pending?.cancel()
        languageRestart.pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.restartLanguageService()
        }
    }

    public func languageContextSettled() async {
        while let t = languageRestart.pending {
            await t.value
            if languageRestart.pending == t { languageRestart.pending = nil }
        }
    }

    public func restartLanguageService() async {
        guard let old = language else { return }
        let documents = old.openTexts
        let applyEdit = old.onApplyEdit
        language = nil
        notify(.issues)
        await old.stop()
        await startLanguageService(transport: languageRestart.makeTransport?())
        languageRestart.count += 1
        guard let new = language else { return }
        new.onApplyEdit = applyEdit
        for (url, text) in documents.sorted(by: { $0.key.path < $1.key.path }) { new.open(url, text: text) }
    }
}
