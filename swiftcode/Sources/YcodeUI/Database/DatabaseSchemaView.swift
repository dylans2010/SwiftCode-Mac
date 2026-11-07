import AppKit
import SwiftUI
import SwiftCodeCloud

@MainActor
struct DatabaseSchemaView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var tables: [DatabaseTable] = []
    @State private var tableOffsets: [String: CGSize] = [:]
    @State private var dragStartOffsets: [String: CGSize] = [:]
    @State private var scale: CGFloat = 1.0
    @State private var loadErrorMessage = ""

    @State private var selectedTab = 0

    @State private var selectedConstraintTable = ""
    @State private var constraintType = "Foreign Key"
    @State private var sourceColumn = ""
    @State private var targetTable = ""
    @State private var targetColumn = ""
    @State private var checkExpression = "age >= 18"
    @State private var constraintLogs = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker("", selection: $selectedTab) {
                    Text("Interactive ER Diagram").tag(0)
                    Text("Constraint & Relationship Designer").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 420)

                Spacer()

                if selectedTab == 0 {
                    Button(action: { scale = max(scale - 0.1, 0.5) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Text("\(Int(scale * 100))%")
                        .font(.caption)
                        .frame(width: 40)
                    Button(action: { scale = min(scale + 0.1, 2.0) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            if !loadErrorMessage.isEmpty {
                Text(loadErrorMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                Divider()
            }

            Divider()

            if selectedTab == 0 {
                ZStack {
                    Color(NSColor.controlBackgroundColor)
                        .opacity(0.3)
                        .ignoresSafeArea()

                    ScrollView([.horizontal, .vertical]) {
                        ZStack {
                            ForEach(tables) { table in
                                ForEach(table.relationships) { rel in
                                    DatabaseSchemaRelationLineView(
                                        sourceOffset: tableOffsets[rel.sourceTable] ?? .zero,
                                        targetOffset: tableOffsets[rel.targetTable] ?? .zero
                                    )
                                }
                            }

                            ForEach(tables) { table in
                                DatabaseSchemaTableCard(table: table)
                                    .offset(tableOffsets[table.name] ?? .zero)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { val in
                                                if dragStartOffsets[table.name] == nil {
                                                    dragStartOffsets[table.name] = tableOffsets[table.name] ?? .zero
                                                }
                                                let base = dragStartOffsets[table.name] ?? .zero
                                                tableOffsets[table.name] = CGSize(
                                                    width: base.width + val.translation.width,
                                                    height: base.height + val.translation.height
                                                )
                                            }
                                            .onEnded { _ in
                                                dragStartOffsets[table.name] = nil
                                            }
                                    )
                            }
                        }
                        .scaleEffect(scale)
                        .frame(width: 1500, height: 1500)
                    }
                }
            } else {
                constraintDesignerPane()
            }
        }
        .onAppear {
            loadTables()
        }
        .alert("Designer Status", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    @ViewBuilder
    private func constraintDesignerPane() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text("Constraint & Relationship Designer")
                        .font(.title2.bold())
                }

                Text("Enforce schema constraints and foreign key mappings. Design table associations and model SQLite relationships visually.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                GroupBox("Constraint Builder") {
                    VStack(alignment: .leading, spacing: 14) {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                            GridRow {
                                Text("Target Table:")
                                    .font(.subheadline.bold())
                                Picker("", selection: $selectedConstraintTable) {
                                    ForEach(tables) { t in
                                        Text(t.name).tag(t.name)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 250)
                            }

                            GridRow {
                                Text("Constraint Type:")
                                    .font(.subheadline.bold())
                                Picker("", selection: $constraintType) {
                                    Text("Foreign Key Relation").tag("Foreign Key")
                                    Text("Unique Rule").tag("Unique")
                                    Text("Check Constraint").tag("Check")
                                }
                                .labelsHidden()
                                .frame(width: 250)
                            }

                            if let currentTableObj = tables.first(where: { $0.name == selectedConstraintTable }) {
                                GridRow {
                                    Text("Source Column:")
                                        .font(.subheadline.bold())
                                    Picker("", selection: $sourceColumn) {
                                        ForEach(currentTableObj.columns) { col in
                                            Text(col.name).tag(col.name)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 250)
                                    .onAppear {
                                        sourceColumn = currentTableObj.columns.first?.name ?? ""
                                    }
                                    .onChange(of: selectedConstraintTable) { _, _ in
                                        sourceColumn = currentTableObj.columns.first?.name ?? ""
                                    }
                                }
                            }

                            if constraintType == "Foreign Key" {
                                GridRow {
                                    Text("Foreign Table:")
                                        .font(.subheadline.bold())
                                    Picker("", selection: $targetTable) {
                                        ForEach(tables.filter { $0.name != selectedConstraintTable }) { t in
                                            Text(t.name).tag(t.name)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 250)
                                    .onAppear {
                                        targetTable = tables.first { $0.name != selectedConstraintTable }?.name ?? ""
                                    }
                                    .onChange(of: selectedConstraintTable) { _, _ in
                                        targetTable = tables.first { $0.name != selectedConstraintTable }?.name ?? ""
                                    }
                                }

                                if let targetTableObj = tables.first(where: { $0.name == targetTable }) {
                                    GridRow {
                                        Text("Foreign Column:")
                                            .font(.subheadline.bold())
                                        Picker("", selection: $targetColumn) {
                                            ForEach(targetTableObj.columns) { col in
                                                Text(col.name).tag(col.name)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 250)
                                        .onAppear {
                                            targetColumn = targetTableObj.columns.first?.name ?? ""
                                        }
                                        .onChange(of: targetTable) { _, _ in
                                            targetColumn = targetTableObj.columns.first?.name ?? ""
                                        }
                                    }
                                }
                            } else if constraintType == "Check" {
                                GridRow {
                                    Text("Check Expression:")
                                        .font(.subheadline.bold())
                                    TextField("e.g., price >= 0", text: $checkExpression)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 250)
                                }
                            }
                        }

                        Button(action: applyConstraintChanges) {
                            Label("Apply Schema Constraint", systemImage: "link.badge.plus")
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(selectedConstraintTable.isEmpty)
                    }
                    .padding(8)
                }

                if !constraintLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DDL Script Preview:")
                            .font(.subheadline.bold())
                        ScrollView {
                            Text(constraintLogs)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(8)
                        }
                        .frame(height: 180)
                    }
                }
            }
            .padding(20)
        }
    }

    private func loadTables() {
        guard let conn = connManager.activeConnection else { return }
        Task { @MainActor in
            do {
                if conn.provider == .sqlite {
                    let explorer = try DatabaseViewSQLite.explorer(for: conn)
                    tables = try DatabaseViewSQLite.fetchTables(explorer)
                    loadErrorMessage = ""
                } else if conn.provider == .supabase {
                    tables = try await SupabaseService().fetchTables(connection: conn)
                    loadErrorMessage = ""
                } else {
                    tables = []
                    loadErrorMessage = "No schema driver for \(conn.provider.rawValue) in this package."
                    return
                }

                var x: CGFloat = 50
                var y: CGFloat = 50
                for table in tables {
                    if tableOffsets[table.name] == nil {
                        tableOffsets[table.name] = CGSize(width: x, height: y)
                        x += 280
                        if x > 1000 {
                            x = 50
                            y += 300
                        }
                    }
                }

                if !tables.isEmpty {
                    selectedConstraintTable = tables.first?.name ?? ""
                }
            } catch {
                tables = []
                loadErrorMessage = error.localizedDescription
            }
        }
    }

    private func applyConstraintChanges() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite else {
            alertMessage = "Applying constraints needs the active SQLite connection."
            showingAlert = true
            return
        }

        var ddl = ""
        if constraintType == "Foreign Key" {
            ddl = "-- SQLite Foreign Key schema alterations require rebuilding tables.\n"
            ddl += "-- Generated migration DDL to define Foreign Key relation:\n\n"
            ddl += "PRAGMA foreign_keys=off;\n"
            ddl += "BEGIN TRANSACTION;\n"
            ddl += "ALTER TABLE \(SQLiteExplorerModel.quoted(selectedConstraintTable)) RENAME TO \(SQLiteExplorerModel.quoted("_\(selectedConstraintTable)_old"));\n"

            if let currentTableObj = tables.first(where: { $0.name == selectedConstraintTable }) {
                var colsDDL: [String] = []
                for col in currentTableObj.columns {
                    var colDef = "\(SQLiteExplorerModel.quoted(col.name)) \(col.type)"
                    if col.isPrimaryKey { colDef += " PRIMARY KEY" }
                    if !col.isNullable { colDef += " NOT NULL" }
                    colsDDL.append(colDef)
                }
                colsDDL.append("FOREIGN KEY (\(SQLiteExplorerModel.quoted(sourceColumn))) REFERENCES \(SQLiteExplorerModel.quoted(targetTable))(\(SQLiteExplorerModel.quoted(targetColumn))) ON DELETE CASCADE")

                ddl += "CREATE TABLE \(SQLiteExplorerModel.quoted(selectedConstraintTable)) (\n  " + colsDDL.joined(separator: ",\n  ") + "\n);\n"

                let colNames = currentTableObj.columns.map { SQLiteExplorerModel.quoted($0.name) }.joined(separator: ", ")
                ddl += "INSERT INTO \(SQLiteExplorerModel.quoted(selectedConstraintTable)) (\(colNames)) SELECT \(colNames) FROM \(SQLiteExplorerModel.quoted("_\(selectedConstraintTable)_old"));\n"
                ddl += "DROP TABLE \(SQLiteExplorerModel.quoted("_\(selectedConstraintTable)_old"));\n"
                ddl += "COMMIT;\n"
                ddl += "PRAGMA foreign_keys=on;\n"
            }
        } else if constraintType == "Unique" {
            ddl = "CREATE UNIQUE INDEX \(SQLiteExplorerModel.quoted("idx_uniq_\(selectedConstraintTable)_\(sourceColumn)")) ON \(SQLiteExplorerModel.quoted(selectedConstraintTable)) (\(SQLiteExplorerModel.quoted(sourceColumn)));"
        } else {
            ddl = "-- SQLite Check constraints must be defined at CREATE TABLE.\n"
            ddl += "-- Schema validation rules:\n"
            ddl += "SELECT case when NOT (\(checkExpression)) then raise(fail, 'Check Constraint Violated!') else 'Passed' end FROM \(SQLiteExplorerModel.quoted(selectedConstraintTable));\n"
        }

        constraintLogs = ddl

        Task { @MainActor in
            do {
                let explorer = try DatabaseViewSQLite.explorer(for: conn)
                if constraintType == "Unique" {
                    _ = try explorer.run(sql: ddl)
                    alertMessage = "Unique constraint index generated successfully!"
                } else if constraintType == "Check" {
                    _ = try explorer.run(sql: "SELECT * FROM \(SQLiteExplorerModel.quoted(selectedConstraintTable)) LIMIT 10;")
                    alertMessage = "Check Constraint validation code generated. Rebuild database schemas during next migration deployment."
                } else {
                    let statements = ddl.components(separatedBy: ";").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    for stmt in statements {
                        _ = try explorer.run(sql: stmt + ";")
                    }
                    alertMessage = "Relationship created and table rebuilt successfully with Foreign Key constraint!"
                }

                showingAlert = true
                loadTables()
            } catch {
                alertMessage = "Alter schema failed: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}

struct DatabaseSchemaRelationLineView: View {
    let sourceOffset: CGSize
    let targetOffset: CGSize

    var body: some View {
        Path { path in
            let startPoint = CGPoint(x: sourceOffset.width + 120, y: sourceOffset.height + 80)
            let endPoint = CGPoint(x: targetOffset.width + 120, y: targetOffset.height + 80)
            path.move(to: startPoint)

            let control1 = CGPoint(x: startPoint.x + 100, y: startPoint.y)
            let control2 = CGPoint(x: endPoint.x - 100, y: endPoint.y)
            path.addCurve(to: endPoint, control1: control1, control2: control2)
        }
        .stroke(Color.blue.opacity(0.4), lineWidth: 2)
    }
}

struct DatabaseSchemaTableCard: View {
    let table: DatabaseTable

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "tablecells.fill")
                    .foregroundColor(.white)
                Text(table.name)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(10)
            .frame(width: 240, alignment: .leading)
            .background(Color.blue)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(table.columns) { col in
                    HStack {
                        if col.isPrimaryKey {
                            Image(systemName: "key.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        } else if col.isForeignKey {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                        } else {
                            Circle()
                                .fill(Color.secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }

                        Text(col.name)
                            .font(.system(size: 11, weight: .medium))

                        Spacer()

                        Text(col.type)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .frame(width: 240)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
}
