import Foundation

public enum ProjectKind: String, Codable, Sendable {
    case xcodeProject
    case swiftPackage
    case folder
}
