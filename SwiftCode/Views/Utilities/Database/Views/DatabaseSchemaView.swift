import SwiftUI

struct DatabaseSchemaView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var tables: [DatabaseTable] = []
    @State private var tableOffsets: [String: CGSize] = [:]
    @State private var scale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Scale and action bar
            HStack {
                Text("Visual Schema Diagram")
                    .font(.headline)
                Spacer()

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
            .padding(10)
            .background(Color.secondary.opacity(0.08))

            Divider()

            ZStack {
                // Background grid pattern
                GeometryReader { _ in
                    Canvas { context, size in
                        let gridWidth: CGFloat = 40
                        var x: CGFloat = 0
                        while x < size.width {
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(path, with: .color(Color.secondary.opacity(0.04)), lineWidth: 1)
                            x += gridWidth
                        }
                        var y: CGFloat = 0
                        while y < size.height {
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            context.stroke(path, with: .color(Color.secondary.opacity(0.04)), lineWidth: 1)
                            y += gridWidth
                        }
                    }
                }

                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        // Lines showing Foreign Key Relationships
                        ForEach(tables) { table in
                            ForEach(table.relationships) { rel in
                                RelationLineView(
                                    sourceOffset: tableOffsets[rel.sourceTable] ?? .zero,
                                    targetOffset: tableOffsets[rel.targetTable] ?? .zero
                                )
                            }
                        }

                        // Tables boxes
                        ForEach(tables) { table in
                            SchemaTableCard(table: table)
                                .offset(tableOffsets[table.name] ?? .zero)
                                .gesture(
                                    DragGesture()
                                        .onChanged { val in
                                            let current = tableOffsets[table.name] ?? .zero
                                            tableOffsets[table.name] = CGSize(
                                                width: current.width + val.translation.width,
                                                height: current.height + val.translation.height
                                            )
                                        }
                                )
                        }
                    }
                    .scaleEffect(scale)
                    .frame(width: 2000, height: 2000)
                }
            }
        }
        .onAppear {
            loadTables()
        }
    }

    private func loadTables() {
        guard let conn = connManager.activeConnection else { return }
        Task {
            do {
                if conn.provider == .sqlite {
                    if let path = conn.sqliteFilePath {
                        tables = try DatabaseManager.shared.fetchSQLiteTables(filePath: path)
                    }
                } else if conn.provider == .supabase {
                    tables = try await SupabaseService.shared.fetchTables(connection: conn)
                }

                // Lay tables out in a grid
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
            } catch {
                print("Failed to load tables: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Relation Line View

struct RelationLineView: View {
    let sourceOffset: CGSize
    let targetOffset: CGSize

    var body: some View {
        Path { path in
            let startPoint = CGPoint(x: sourceOffset.width + 120, y: sourceOffset.height + 80)
            let endPoint = CGPoint(x: targetOffset.width + 120, y: targetOffset.height + 80)
            path.move(to: startPoint)

            // Curved cubic bezier line
            let control1 = CGPoint(x: startPoint.x + 100, y: startPoint.y)
            let control2 = CGPoint(x: endPoint.x - 100, y: endPoint.y)
            path.addCurve(to: endPoint, control1: control1, control2: control2)
        }
        .stroke(Color.blue.opacity(0.4), lineWidth: 2)
    }
}

// MARK: - Schema Table Card

struct SchemaTableCard: View {
    let table: DatabaseTable

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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

            // Columns
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
