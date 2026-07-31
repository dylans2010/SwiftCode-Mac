import SwiftUI

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
                .frame(width: 500, height: 450)
        }
    }
}
