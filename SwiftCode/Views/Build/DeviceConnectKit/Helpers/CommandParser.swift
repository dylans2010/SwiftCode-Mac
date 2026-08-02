import Foundation

public struct CommandParser {
    public static func parseJSON<T: Decodable>(_ dataString: String, as type: T.Type) -> T? {
        guard let data = dataString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public static func splitLines(_ output: String) -> [String] {
        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
