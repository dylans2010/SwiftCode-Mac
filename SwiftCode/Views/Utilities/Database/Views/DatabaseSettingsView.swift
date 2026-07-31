import SwiftUI

struct DatabaseSettingsView: View {
    @State private var enableAutosave = true
    @State private var maxHistoryCount = 100
    @State private var defaultSQLDialect = "SQLite"
    @State private var useSSLForPostgres = true

    var body: some View {
        Form {
            Section("General Database Configuration") {
                Toggle("Enable Schema Autosave", isOn: $enableAutosave)

                Picker("Max Query History Count", selection: $maxHistoryCount) {
                    Text("50 entries").tag(50)
                    Text("100 entries").tag(100)
                    Text("200 entries").tag(200)
                }

                Picker("Default SQL Dialect", selection: $defaultSQLDialect) {
                    Text("SQLite").tag("SQLite")
                    Text("PostgreSQL").tag("PostgreSQL")
                    Text("MySQL").tag("MySQL")
                }
            }

            Section("Remote Connection Preferences") {
                Toggle("Enforce SSL/TLS for PostgreSQL connections", isOn: $useSSLForPostgres)
            }
        }
        .formStyle(.grouped)
    }
}
