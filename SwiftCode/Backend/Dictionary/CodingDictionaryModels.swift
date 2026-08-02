import Foundation

public struct DictionaryParameter: Codable, Sendable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let description: String

    public init(name: String, type: String, description: String) {
        self.name = name
        self.type = type
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

public struct DictionaryReturnValue: Codable, Sendable, Equatable {
    public let type: String
    public let description: String

    public init(type: String, description: String) {
        self.type = type
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

public struct DictionaryExample: Codable, Sendable, Identifiable, Equatable {
    public var id: String { title }
    public let title: String
    public let code: String

    public init(title: String, code: String) {
        self.title = title
        self.code = code
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.code = try container.decodeIfPresent(String.self, forKey: .code) ?? ""
    }
}

public struct DictionaryMistake: Codable, Sendable, Identifiable, Equatable {
    public var id: String { description }
    public let description: String
    public let explanation: String
    public let fix: String

    public init(description: String, explanation: String, fix: String) {
        self.description = description
        self.explanation = explanation
        self.fix = fix
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        self.fix = try container.decodeIfPresent(String.self, forKey: .fix) ?? ""
    }
}

public struct CodingDictionaryResult: Codable, Sendable, Equatable {
    public let version: String
    public let confidence: Int
    public let query: String
    public let title: String
    public let subtitle: String
    public let kind: String
    public let category: String
    public let difficulty: String
    public let overview: String
    public let definition: String
    public let summary: String
    public let syntax: String
    public let parameters: [DictionaryParameter]
    public let returnValue: DictionaryReturnValue
    public let examples: [DictionaryExample]
    public let commonMistakes: [DictionaryMistake]
    public let bestPractices: [String]
    public let performanceNotes: String
    public let threadSafety: String
    public let securityNotes: String
    public let availability: [String]
    public let relatedConcepts: [String]
    public let aliases: [String]
    public let keywords: [String]
    public let warnings: [String]
    public let notes: [String]
    public let seeAlso: [String]
    public let references: [String]

    public init(
        version: String = "1.0",
        confidence: Int = 100,
        query: String = "",
        title: String = "",
        subtitle: String = "",
        kind: String = "",
        category: String = "",
        difficulty: String = "",
        overview: String = "",
        definition: String = "",
        summary: String = "",
        syntax: String = "",
        parameters: [DictionaryParameter] = [],
        returnValue: DictionaryReturnValue = DictionaryReturnValue(type: "", description: ""),
        examples: [DictionaryExample] = [],
        commonMistakes: [DictionaryMistake] = [],
        bestPractices: [String] = [],
        performanceNotes: String = "",
        threadSafety: String = "",
        securityNotes: String = "",
        availability: [String] = [],
        relatedConcepts: [String] = [],
        aliases: [String] = [],
        keywords: [String] = [],
        warnings: [String] = [],
        notes: [String] = [],
        seeAlso: [String] = [],
        references: [String] = []
    ) {
        self.version = version
        self.confidence = confidence
        self.query = query
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.category = category
        self.difficulty = difficulty
        self.overview = overview
        self.definition = definition
        self.summary = summary
        self.syntax = syntax
        self.parameters = parameters
        self.returnValue = returnValue
        self.examples = examples
        self.commonMistakes = commonMistakes
        self.bestPractices = bestPractices
        self.performanceNotes = performanceNotes
        self.threadSafety = threadSafety
        self.securityNotes = securityNotes
        self.availability = availability
        self.relatedConcepts = relatedConcepts
        self.aliases = aliases
        self.keywords = keywords
        self.warnings = warnings
        self.notes = notes
        self.seeAlso = seeAlso
        self.references = references
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
        self.confidence = try container.decodeIfPresent(Int.self, forKey: .confidence) ?? 100
        self.query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        self.kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        self.category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        self.difficulty = try container.decodeIfPresent(String.self, forKey: .difficulty) ?? ""
        self.overview = try container.decodeIfPresent(String.self, forKey: .overview) ?? ""
        self.definition = try container.decodeIfPresent(String.self, forKey: .definition) ?? ""
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        self.syntax = try container.decodeIfPresent(String.self, forKey: .syntax) ?? ""
        self.parameters = try container.decodeIfPresent([DictionaryParameter].self, forKey: .parameters) ?? []
        self.returnValue = try container.decodeIfPresent(DictionaryReturnValue.self, forKey: .returnValue) ?? DictionaryReturnValue(type: "", description: "")
        self.examples = try container.decodeIfPresent([DictionaryExample].self, forKey: .examples) ?? []
        self.commonMistakes = try container.decodeIfPresent([DictionaryMistake].self, forKey: .commonMistakes) ?? []
        self.bestPractices = try container.decodeIfPresent([String].self, forKey: .bestPractices) ?? []
        self.performanceNotes = try container.decodeIfPresent(String.self, forKey: .performanceNotes) ?? ""
        self.threadSafety = try container.decodeIfPresent(String.self, forKey: .threadSafety) ?? ""
        self.securityNotes = try container.decodeIfPresent(String.self, forKey: .securityNotes) ?? ""
        self.availability = try container.decodeIfPresent([String].self, forKey: .availability) ?? []
        self.relatedConcepts = try container.decodeIfPresent([String].self, forKey: .relatedConcepts) ?? []
        self.aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        self.keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        self.warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        self.notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
        self.seeAlso = try container.decodeIfPresent([String].self, forKey: .seeAlso) ?? []
        self.references = try container.decodeIfPresent([String].self, forKey: .references) ?? []
    }
}
