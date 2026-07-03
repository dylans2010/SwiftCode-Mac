import Foundation

public enum BuildConfiguration: String, CaseIterable, Sendable, Codable {
    case debug = "Debug"
    case release = "Release"
}
