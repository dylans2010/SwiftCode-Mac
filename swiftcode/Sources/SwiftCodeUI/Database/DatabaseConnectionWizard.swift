import AppKit
import SwiftUI
import SwiftCodeCloud
import UniformTypeIdentifiers

/// Creates a saved `DatabaseConnection` through
/// `DatabaseConnectionManager`.
///
/// Ported from Legacy's
/// `Views/Utilities/Database/Views/DatabaseConnectionWizard.swift`.
///
/// Changes over Legacy, all recorded here:
///
/// - Legacy's `liquidGlass` header is gone (SwiftCodeUI has no
///   such modifier); the header is a plain row on a subtle
///   background.
/// - The wizard now also collects the two optional Supabase
///   credentials Legacy's `DatabaseConnection` already carried but
///   the wizard never asked for (service key and JWT secret, as
///   secure fields, never given a default).
/// - `SupabaseService` is the destination's value type
///   (`SupabaseService()` — no `.shared`); this wizard only
///   records the connection, it does not test it (the connections
///   list tests it).
@MainActor
struct DatabaseConnectionWizard: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var connManager: DatabaseConnectionManager

    @State private var provider: DatabaseProvider = .sqlite
    @State private var name = ""
    @State private var sqliteFilePath = ""
    @State private var host = "127.0.0.1"
    @State private var port = 5432
    @State private var databaseName = ""
    @State private var username = ""

    // Supabase
    @State private var supabaseURL = ""
    @State private var supabaseAnonKey = ""
    @State private var supabaseServiceKey = ""
    @State private var supabaseJWTSecret = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Database Connection Wizard")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            .background(Color.secondary.opacity(0.06))

            Form {
                Picker("Database Engine", selection: $provider) {
                    ForEach(DatabaseProvider.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }

                TextField("Connection Name", text: $name)

                if provider == .sqlite {
                    Section("SQLite Configuration") {
                        TextField("Database File Path", text: $sqliteFilePath)
                        Button("Select File Path...") {
                            selectFilePath()
                        }
                    }
                } else if provider == .supabase {
                    Section("Supabase Configuration") {
                        TextField("Supabase Project URL", text: $supabaseURL)
                        TextField("Anonymous / Public API Key", text: $supabaseAnonKey)
                        SecureField("Service Role Key (optional)", text: $supabaseServiceKey)
                        SecureField("JWT Secret (optional)", text: $supabaseJWTSecret)
                    }
                } else {
                    Section("Connection Parameters") {
                        TextField("Server Hostname / IP", text: $host)
                        TextField("Server Port", value: $port, format: .number)
                        TextField("Database Name", text: $databaseName)
                        TextField("Username", text: $username)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Connect Database") {
                    saveConnection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
            .padding()
        }
    }

    private func selectFilePath() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.database, .data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            sqliteFilePath = url.path
        }
    }

    private func saveConnection() {
        let conn = DatabaseConnection(
            name: name,
            provider: provider,
            sqliteFilePath: sqliteFilePath.isEmpty ? nil : sqliteFilePath,
            host: host.isEmpty ? nil : host,
            port: port,
            databaseName: databaseName.isEmpty ? nil : databaseName,
            username: username.isEmpty ? nil : username,
            supabaseURL: supabaseURL.isEmpty ? nil : supabaseURL,
            supabaseAnonKey: supabaseAnonKey.isEmpty ? nil : supabaseAnonKey,
            supabaseServiceKey: supabaseServiceKey.isEmpty ? nil : supabaseServiceKey,
            supabaseJWTSecret: supabaseJWTSecret.isEmpty ? nil : supabaseJWTSecret
        )
        connManager.addConnection(conn)
        dismiss()
    }
}
