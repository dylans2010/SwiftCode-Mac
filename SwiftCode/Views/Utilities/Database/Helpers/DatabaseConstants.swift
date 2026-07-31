import Foundation

public struct DatabaseConstants {
    public static let standardSQLiteTypes = ["INTEGER", "TEXT", "REAL", "BLOB", "NULL"]

    public static let standardPostgresTypes = [
        "INTEGER", "BIGINT", "SMALLINT", "SERIAL", "BIGSERIAL",
        "VARCHAR(255)", "TEXT", "UUID", "BOOLEAN", "DATE",
        "TIMESTAMP", "TIMESTAMPTZ", "JSON", "JSONB", "NUMERIC", "REAL"
    ]

    public static let standardMySQLTypes = [
        "INT", "BIGINT", "SMALLINT", "TINYINT",
        "VARCHAR(255)", "TEXT", "LONGTEXT", "TINYINT(1)", "DATE",
        "DATETIME", "TIMESTAMP", "JSON", "DECIMAL", "DOUBLE"
    ]
}
