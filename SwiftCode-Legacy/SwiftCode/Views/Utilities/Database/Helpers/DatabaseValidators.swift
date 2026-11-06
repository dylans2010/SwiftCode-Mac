import Foundation

public struct DatabaseValidators {
    public static func validateTableName(_ name: String) -> (isValid: Bool, message: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (false, "Table name cannot be empty.")
        }

        let characterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if trimmed.rangeOfCharacter(from: characterSet.inverted) != nil {
            return (false, "Table name must only contain alphanumeric characters or underscores.")
        }

        if let firstChar = trimmed.first, firstChar.isNumber {
            return (false, "Table name cannot start with a number.")
        }

        return (true, "Valid table name.")
    }

    public static func validateColumnName(_ name: String) -> (isValid: Bool, message: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (false, "Column name cannot be empty.")
        }

        let characterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if trimmed.rangeOfCharacter(from: characterSet.inverted) != nil {
            return (false, "Column name must only contain alphanumeric characters or underscores.")
        }

        return (true, "Valid column name.")
    }
}
