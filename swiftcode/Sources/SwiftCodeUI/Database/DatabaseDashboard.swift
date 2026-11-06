// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/Utilities/Database/Views/DatabaseDashboard.swift
//   (Legacy main ab03f681)
//
// Destination: SwiftCodeUI/Database/DatabaseDashboard.swift.
//
// !!! NAME COLLISION — READ BEFORE LANDING !!!
// This file declares the SwiftUI view `DatabaseDashboard`. The same name
// is already the model class in SwiftCodeIDECore
// (`SwiftCodeIDECore/Model/Database/DatabaseDashboard.swift`), and
// `SwiftCodeUI/Database/SQLiteExplorerSectionsController.swift` uses that
// class unqualified in TWO places (lines ~48 and ~80:
// `private let dashboard: DatabaseDashboard` and
// `self.dashboard = DatabaseDashboard(db: db)`). Landing this file as-is
// makes those two references resolve to THIS view struct and breaks the
// SQLite Explorer build. Landing MUST qualify them first:
// `SwiftCodeIDECore.DatabaseDashboard` in both places. (The batch-2
// split-controller header flags the same collision: "the Views port must
// qualify or rename it" — this port qualifies the existing model use.)
// The Legacy view name is kept deliberately: the split controller staged
// alongside this file hosts `DatabaseDashboard(selectedSection:)` by that
// name, and the migration ledger tracks the Legacy name.
//
// Adaptations (behaviour preserved unless noted):
// * Legacy's two hardcoded metric values are wired to live readings
//   instead of carried over: "3 Migrations" and "100/100" were literals
//   in Legacy, and the health card's "Passed (0.1ms latency)" and the
//   "PostgREST protocol pipelines are fully connected" claim were too.
//   The view now loads `DatabaseDashboardStats` from the destination's
//   `DatabaseDashboard` model (same name, other module — see the
//   collision note) for the active connection's SQLite file and shows
//   the real migration count, the real health-check pass ratio and the
//   real integrity result; with no active SQLite connection it shows
//   "—" / "No active SQLite connection" instead of inventing numbers.
//   The other two metric cards were already live (active connection
//   name, tracked-profile count) and are unchanged.
// * `.groupBoxStyle(.liquidGlass)` has no destination equivalent —
//   SwiftCode draws no glass of its own making — so the health card
//   uses `.groupBoxStyle(ModernGroupBoxStyle())` (this target).
// * `import SwiftCodeIDECore` (dashboard model) and
//   `import SwiftCodeHealthStore` (SQLiteDatabase) added; SwiftCodeUI
//   already depends on both.

import SwiftUI
import SwiftCodeHealthStore
import SwiftCodeIDECore

struct DatabaseDashboard: View {
    @Binding var selectedSection: DatabaseSection
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var stats: DatabaseDashboardStats?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Hero
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "tablecells.badge.ellipsis")
                            .font(.largeTitle)
                            .foregroundColor(.green)
                        Text("Database Management Studio")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                    Text("Design visual schemas, execute interactive SQL, manage migrations, track performance, and generate SwiftData models with AI assistance.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Statistics Summary Grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                    DashboardMetricCard(title: "Active DB Connection", value: connManager.activeConnection?.name ?? "None", icon: "cylinder.split.1x2.fill", color: .blue)
                    DashboardMetricCard(title: "Total Tracked Profiles", value: "\(connManager.connections.count)", icon: "network", color: .orange)
                    DashboardMetricCard(title: "Migrations & History", value: stats.map { "\($0.migrationCount) Migrations" } ?? "—", icon: "arrow.triangle.2.circlepath", color: .green)
                    DashboardMetricCard(title: "Diagnostics Health Index", value: healthIndexText, icon: "heart.text.square.fill", color: .red)
                }

                Divider()

                // Quick Launch Studio Views (Exposing ALL features cleanly)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Exposed DBA Utilities & Workspaces")
                        .font(.title3.bold())
                        .foregroundColor(.primary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 16) {
                        QuickActionLaunchCard(
                            title: "Tables & View Explorer",
                            desc: "Inspect SQLite tables, constraints, column properties, and trigger definitions.",
                            icon: "tablecells",
                            color: .blue
                        ) {
                            selectedSection = .tables
                        }

                        QuickActionLaunchCard(
                            title: "Visual Schema Designer",
                            desc: "Render ER diagrams, model relationship maps, and export visual schema comparisons.",
                            icon: "point.topleft.down.to.point.bottomright.curvepath",
                            color: .orange
                        ) {
                            selectedSection = .schemaDesigner
                        }

                        QuickActionLaunchCard(
                            title: "SQL Query Editor & Runner",
                            desc: "Format SQL queries, track execution query history, and organize saved scripts.",
                            icon: "terminal",
                            color: .green
                        ) {
                            selectedSection = .sqlEditor
                        }

                        QuickActionLaunchCard(
                            title: "Migration Generator & History",
                            desc: "Generate incremental migrations, verify schema comparison diffs, and deploy to Supabase.",
                            icon: "arrow.triangle.2.circlepath",
                            color: .cyan
                        ) {
                            selectedSection = .migrations
                        }

                        QuickActionLaunchCard(
                            title: "Backup & Restore Engine",
                            desc: "Compress, encrypt, and schedule snapshots to Supabase Storage or Apple iCloud.",
                            icon: "archivebox",
                            color: .purple
                        ) {
                            selectedSection = .backups
                        }

                        QuickActionLaunchCard(
                            title: "Dataset Import & Export",
                            desc: "Import and export files seamlessly in CSV, JSON, SQLite, and custom SQL formats.",
                            icon: "arrow.up.and.down.and.arrow.left.and.right",
                            color: .pink
                        ) {
                            selectedSection = .importExport
                        }

                        QuickActionLaunchCard(
                            title: "Structural DB Templates",
                            desc: "Apply ready-to-run template structures matching real-world SQLite structures.",
                            icon: "square.stack.3d.up",
                            color: .yellow
                        ) {
                            selectedSection = .templates
                        }

                        QuickActionLaunchCard(
                            title: "AI Database Architect",
                            desc: "Ask Codex to generate SwiftData/Codable code models, compile validation rules, and write SQL.",
                            icon: "sparkles",
                            color: .indigo
                        ) {
                            selectedSection = .aiAssistant
                        }

                        QuickActionLaunchCard(
                            title: "Performance Profiler",
                            desc: "Analyze storage usage, explain execution plans, and run database query analyzers.",
                            icon: "gauge.with.needle",
                            color: .red
                        ) {
                            selectedSection = .performance
                        }

                        QuickActionLaunchCard(
                            title: "Execution Logs & Stats",
                            desc: "View direct execution stats, query timers, and PostgREST connection errors.",
                            icon: "doc.text",
                            color: .gray
                        ) {
                            selectedSection = .logs
                        }

                        QuickActionLaunchCard(
                            title: "Connection Profiles & Setup",
                            desc: "Manage profiles, credentials, storage buckets, and run diagnostic ping handshakes.",
                            icon: "gearshape",
                            color: .teal
                        ) {
                            selectedSection = .settings
                        }
                    }
                }

                Divider()

                // Health Summary Card
                GroupBox("Diagnostics & Real-time Monitor") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.title)
                                .foregroundColor(.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Database Engine Status")
                                    .font(.headline)
                                Text(engineStatusText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        Divider()

                        HStack {
                            Label("Integrity Check:", systemImage: "bolt.horizontal.fill")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Text(integrityText)
                                .font(.caption)
                                .foregroundColor(.green)
                            Spacer()
                        }
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .task(id: connManager.activeConnection?.id) {
            await loadStats()
        }
    }

    private var healthIndexText: String {
        guard let stats else { return "—" }
        let passed = stats.healthChecks.filter(\.passed).count
        return "\(passed)/\(stats.healthChecks.count)"
    }

    private var engineStatusText: String {
        guard let stats else { return "No active SQLite connection — connect a database to run diagnostics." }
        return "SQLite engine connected — integrity: \(stats.integrity), \(stats.tableCount) tables, \(stats.totalRows) rows."
    }

    private var integrityText: String {
        stats?.integrity ?? "Not run"
    }

    /// Live dashboard stats for the active connection's SQLite file.
    /// Non-SQLite connections and failures leave `stats` nil, which the
    /// cards render as "—" rather than inventing numbers.
    private func loadStats() async {
        guard let path = connManager.activeConnection?.sqliteFilePath else {
            stats = nil
            return
        }
        do {
            let db = try SQLiteDatabase(path: path)
            let model = SwiftCodeIDECore.DatabaseDashboard(db: db)
            stats = try model.stats()
        } catch {
            stats = nil
        }
    }
}

struct QuickActionLaunchCard: View {
    let title: String
    let desc: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundColor(color)
                    }
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                }

                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(height: 44, alignment: .top)
            }
            .padding(14)
            .background(Color.secondary.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct DashboardMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}
