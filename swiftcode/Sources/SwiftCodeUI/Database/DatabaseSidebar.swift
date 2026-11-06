import SwiftUI
import SwiftCodeCloud

/// Connection picker + twelve-section workspace navigation.
///
/// Ported from Legacy's
/// `Views/Utilities/Database/Views/DatabaseSidebar.swift`.
///
/// Changes over Legacy, all recorded here:
///
/// - `DatabaseSection` is NOT redeclared here: the staged sibling
///   `DatabaseExplorerSidebarViewController.swift` already defines
///   it (public, same twelve cases and icons, ported from Legacy's
///   `DatabaseExplorerView.swift`). This view uses that definition.
/// - The wizard sheet now receives the connection manager
///   explicitly (`.environmentObject(connManager)`). Legacy's
///   sidebar held the manager as an `@ObservedObject`, not from
///   the environment, so the sheet's `DatabaseConnectionWizard`
///   — which reads it as an `@EnvironmentObject` — had nothing to
///   read from and would have failed at runtime.
/// - Legacy's `liquidGlass` header is gone (SwiftCodeUI has no
///   such modifier); the header is a plain row on a subtle
///   background.
/// - This sidebar selects which workspace section the split view
///   shows. It does not duplicate the SQLite Explorer's sections
///   panel (`SQLiteExplorerSectionsController`): that panel renders
///   dashboard / migrations / backups / import-export / templates
///   / AI / performance / logs over a live SQLite file, while this
///   sidebar adds tables & views, the schema designer, the SQL
///   editor, and settings, and is connection-oriented rather than
///   file-oriented.
@MainActor
struct DatabaseSidebar: View {
    @Binding var selectedSection: DatabaseSection
    @ObservedObject var connManager: DatabaseConnectionManager
    @State private var showingWizard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Connection Picker Section
            VStack(alignment: .leading, spacing: 6) {
                Text("CONNECTION")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                HStack {
                    Picker("", selection: $connManager.activeConnection) {
                        ForEach(connManager.connections) { conn in
                            Text(conn.name).tag(conn as DatabaseConnection?)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Button {
                        showingWizard = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Connect New Database")
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.06))

            Divider()

            // Sections Navigation List
            List(DatabaseSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    HStack(spacing: 8) {
                        Image(systemName: section.icon)
                            .foregroundColor(.blue)
                            .frame(width: 16)
                        Text(section.rawValue)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .sheet(isPresented: $showingWizard) {
            DatabaseConnectionWizard()
                .environmentObject(connManager)
                .frame(width: 500, height: 450)
        }
    }
}
