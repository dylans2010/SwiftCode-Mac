import Foundation

public struct PredictionResult: Sendable, Equatable {
    public var text: String
    public var raw: String
    public var model: String?
    public var firstTokenMilliseconds: Double?
    public var totalMilliseconds: Double
    public var stoppedEarly: Bool
}

public struct PredictionClient: Sendable {
    public var backend: PredictionBackend
    public var shaper: SuggestionShaper

    public init(backend: PredictionBackend, shaper: SuggestionShaper = SuggestionShaper()) {
        self.backend = backend
        self.shaper = shaper
    }

    public func complete(_ request: PredictionRequest, isolation: isolated (any Actor)? = #isolation,
                         onUpdate: ((String) -> Void)? = nil) async throws -> PredictionResult {
        let clock = ContinuousClock()
        let start = clock.now
        func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        var raw = ""
        var model: String?
        var chat = false
        var first: Double?
        var shown = ""
        var early = false
        for try await e in backend.stream(request) {
            switch e {
            case .model(let m): model = m
            case .chat: chat = true
            case .text(let t):
                if first == nil { first = ms(clock.now - start) }
                raw += t
                let r = shaper.shape(raw, context: request.context, final: false, fromChat: chat)
                if r.text != shown {
                    shown = r.text
                    onUpdate?(shown)
                }
                if r.complete {
                    early = true
                    break
                }
            }
            if early { break }
        }
        try Task.checkCancellation()
        let final = shaper.shape(raw, context: request.context, final: true, fromChat: chat)
        if final.text != shown { onUpdate?(final.text) }
        return PredictionResult(text: final.text, raw: raw, model: model ?? (request.model.isEmpty ? nil : request.model),
                                firstTokenMilliseconds: first, totalMilliseconds: ms(clock.now - start), stoppedEarly: early)
    }
}
