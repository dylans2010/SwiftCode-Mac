import Foundation

public enum FIMFormat: String, Codable, Sendable, CaseIterable {
    case auto
    case qwen
    case starCoder
    case codeLlama
    case deepSeek
    case suffixFirst
    case chat

    public var displayName: String {
        switch self {
        case .auto: "Automatic"
        case .qwen: "Qwen2.5-Coder tokens"
        case .starCoder: "StarCoder tokens"
        case .codeLlama: "Code Llama tokens"
        case .deepSeek: "DeepSeek-Coder tokens"
        case .suffixFirst: "Suffix-first tokens"
        case .chat: "Chat (no FIM tokens)"
        }
    }

    public static func detect(model: String) -> FIMFormat {
        let m = model.lowercased()
        if m.contains("qwen") { return .qwen }
        if m.contains("starcoder") || m.contains("granite") { return .starCoder }
        if m.contains("codellama") || m.contains("code-llama") { return .codeLlama }
        if m.contains("deepseek") { return .deepSeek }
        if m.contains("codestral") { return .suffixFirst }
        return .chat
    }

    public func resolved(model: String) -> FIMFormat { self == .auto ? Self.detect(model: model) : self }

    public func prompt(_ c: CompletionContext, repository: String = "workspace") -> String? {
        switch self {
        case .auto, .chat: return nil
        case .qwen:
            var s = ""
            if !c.related.isEmpty {
                s += "<|repo_name|>\(repository)\n"
                for r in c.related { s += "<|file_sep|>\(r.path)\n\(r.text)\n" }
                s += "<|file_sep|>\(c.path)\n"
            }
            return s + "<|fim_prefix|>\(c.prefix)<|fim_suffix|>\(c.suffix)<|fim_middle|>"
        case .starCoder:
            var s = ""
            for r in c.related { s += "<file_sep>\(r.path)\n\(r.text)\n" }
            if !c.related.isEmpty { s += "<file_sep>\(c.path)\n" }
            return s + "<fim_prefix>\(c.prefix)<fim_suffix>\(c.suffix)<fim_middle>"
        case .codeLlama:
            return "<PRE> \(c.prefix) <SUF>\(c.suffix) <MID>"
        case .deepSeek:
            return "<｜fim▁begin｜>\(c.prefix)<｜fim▁hole｜>\(c.suffix)<｜fim▁end｜>"
        case .suffixFirst:
            return "[SUFFIX]\(c.suffix)[PREFIX]\(c.prefix)"
        }
    }

    public var stop: [String] {
        switch self {
        case .auto, .chat: []
        case .qwen: ["<|endoftext|>", "<|file_sep|>", "<|fim_prefix|>", "<|fim_suffix|>", "<|fim_middle|>", "<|repo_name|>", "<|im_end|>"]
        case .starCoder: ["<|endoftext|>", "<file_sep>", "<fim_prefix>", "<fim_suffix>", "<fim_middle>"]
        case .codeLlama: ["<EOT>", "<PRE>", "<SUF>", "<MID>"]
        case .deepSeek: ["<｜end▁of▁sentence｜>", "<｜fim▁begin｜>", "<｜fim▁hole｜>", "<｜fim▁end｜>"]
        case .suffixFirst: ["[PREFIX]", "[SUFFIX]", "</s>"]
        }
    }

    public static func chatMessages(_ c: CompletionContext) -> [[String: String]] {
        let lang = c.language ?? ""
        return [
            ["role": "system", "content": "You are a code completion engine. Reply with only the code that belongs at <CURSOR>: no explanation, no code fences, and nothing that is already before or after the cursor."],
            ["role": "user", "content": "File: \(c.path)\n```\(lang)\n\(c.prefix)<CURSOR>\(c.suffix)\n```"],
        ]
    }
}
