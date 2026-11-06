import Foundation

@MainActor
public final class DatabaseTemplateManager: ObservableObject {
    public static let shared = DatabaseTemplateManager()

    @Published public var templates: [DatabaseTemplate] = []

    private init() {
        loadTemplates()
        if templates.isEmpty {
            seedDefaultTemplates()
        }
    }

    public func addTemplate(_ template: DatabaseTemplate) {
        templates.append(template)
        saveTemplates()
    }

    public func toggleFavorite(_ template: DatabaseTemplate) {
        if let idx = templates.firstIndex(where: { $0.id == template.id }) {
            templates[idx].isFavorite.toggle()
            saveTemplates()
        }
    }

    private func seedDefaultTemplates() {
        let authTemplate = DatabaseTemplate(
            name: "User Authentication",
            category: "Authentication",
            description: "Production-grade schema for user signups, credentials, roles, and profiles.",
            tags: ["Security", "Users", "Auth"],
            tables: [
                DatabaseTable(name: "users", columns: [
                    DatabaseColumn(name: "id", type: "UUID", isPrimaryKey: true, isNullable: false),
                    DatabaseColumn(name: "email", type: "VARCHAR(255)", isPrimaryKey: false, isNullable: false, isUnique: true),
                    DatabaseColumn(name: "password_hash", type: "TEXT", isPrimaryKey: false, isNullable: false),
                    DatabaseColumn(name: "created_at", type: "TIMESTAMP", isPrimaryKey: false, isNullable: false, defaultValue: "CURRENT_TIMESTAMP")
                ]),
                DatabaseTable(name: "profiles", columns: [
                    DatabaseColumn(name: "user_id", type: "UUID", isPrimaryKey: true, isForeignKey: true, isNullable: false),
                    DatabaseColumn(name: "display_name", type: "VARCHAR(255)"),
                    DatabaseColumn(name: "avatar_url", type: "TEXT")
                ], relationships: [
                    DatabaseRelationship(type: .oneToOne, sourceTable: "profiles", sourceColumn: "user_id", targetTable: "users", targetColumn: "id")
                ])
            ]
        )

        let ecomTemplate = DatabaseTemplate(
            name: "E-Commerce System",
            category: "E-Commerce",
            description: "Scalable schema containing users, products, orders, and structured line items.",
            tags: ["Sales", "Products", "Billing"],
            tables: [
                DatabaseTable(name: "products", columns: [
                    DatabaseColumn(name: "id", type: "INTEGER", isPrimaryKey: true, isAutoIncrement: true),
                    DatabaseColumn(name: "sku", type: "VARCHAR(50)", isPrimaryKey: false, isNullable: false, isUnique: true),
                    DatabaseColumn(name: "name", type: "VARCHAR(255)", isPrimaryKey: false, isNullable: false),
                    DatabaseColumn(name: "price", type: "REAL", isPrimaryKey: false, isNullable: false),
                    DatabaseColumn(name: "stock_quantity", type: "INTEGER", isPrimaryKey: false, isNullable: false, defaultValue: "0")
                ]),
                DatabaseTable(name: "orders", columns: [
                    DatabaseColumn(name: "id", type: "INTEGER", isPrimaryKey: true, isAutoIncrement: true),
                    DatabaseColumn(name: "user_id", type: "UUID", isPrimaryKey: false, isNullable: false),
                    DatabaseColumn(name: "total_amount", type: "REAL", isPrimaryKey: false, isNullable: false),
                    DatabaseColumn(name: "ordered_at", type: "TIMESTAMP", isPrimaryKey: false, isNullable: false, defaultValue: "CURRENT_TIMESTAMP")
                ])
            ]
        )

        templates = [authTemplate, ecomTemplate]
        saveTemplates()
    }

    private func loadTemplates() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.database.templates"),
           let decoded = try? JSONDecoder().decode([DatabaseTemplate].self, from: data) {
            self.templates = decoded
        }
    }

    private func saveTemplates() {
        if let encoded = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(encoded, forKey: "com.swiftcode.database.templates")
        }
    }
}
