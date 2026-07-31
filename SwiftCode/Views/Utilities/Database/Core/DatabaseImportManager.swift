import Foundation

public final class DatabaseImportManager {
    public static let shared = DatabaseImportManager()

    private init() {}

    public func parseCSV(content: String) -> (columns: [String], rows: [[String: String]]) {
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let firstLine = lines.first else { return ([], []) }

        let columns = firstLine.components(separatedBy: ",")
        var rows: [[String: String]] = []

        for line in lines.dropFirst() {
            let fields = line.components(separatedBy: ",")
            var rowDict: [String: String] = [:]
            for (idx, col) in columns.enumerated() {
                if idx < fields.count {
                    rowDict[col] = fields[idx]
                }
            }
            rows.append(rowDict)
        }

        return (columns, rows)
    }
}
