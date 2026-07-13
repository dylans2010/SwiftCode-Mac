import Foundation

public struct ModuleFieldSchema: Sendable, Codable {
    public var fields: [FieldDefinition]

    public struct FieldDefinition: Sendable, Codable, Identifiable {
        public var id: String { name }
        public let name: String
        public let label: String
        public let type: FieldType
        public let isRequired: Bool

        public init(name: String, label: String, type: FieldType, isRequired: Bool = false) {
            self.name = name
            self.label = label
            self.type = type
            self.isRequired = isRequired
        }
    }

    public enum FieldType: String, Sendable, Codable {
        case text
        case paragraph
        case select
        case date
        case boolean
    }

    public static func schema(for kind: ModuleKind) -> ModuleFieldSchema {
        switch kind {
        case .bugDatabase:
            return ModuleFieldSchema(fields: [
                FieldDefinition(name: "severity", label: "Severity", type: .select),
                FieldDefinition(name: "reproSteps", label: "Reproduction Steps", type: .paragraph),
                FieldDefinition(name: "stackTrace", label: "Stack Trace", type: .paragraph),
                FieldDefinition(name: "status", label: "Status", type: .select)
            ])
        case .featurePlanning, .techDebtTracker, .milestones:
            return ModuleFieldSchema(fields: [
                FieldDefinition(name: "priority", label: "Priority", type: .select),
                FieldDefinition(name: "status", label: "Status", type: .select),
                FieldDefinition(name: "targetDate", label: "Target Date", type: .date)
            ])
        case .roadmap, .releasePlanning:
            return ModuleFieldSchema(fields: [
                FieldDefinition(name: "targetQuarter", label: "Target Quarter", type: .select),
                FieldDefinition(name: "status", label: "Status", type: .select)
            ])
        default:
            return ModuleFieldSchema(fields: [
                FieldDefinition(name: "status", label: "Status", type: .select)
            ])
        }
    }
}
