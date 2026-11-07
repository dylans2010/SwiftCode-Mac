import Foundation
import os.log

@MainActor
public final class DatabaseAIService {
    public static let shared = DatabaseAIService()
    private let logger = Logger(subsystem: "com.SwiftCode", category: "DatabaseAIService")

    private init() {}

    public func generateDatabaseArchitecture(prompt: String) async throws -> String {
        let systemContext = """
You are a highly skilled, senior Database Architect. Your task is to generate complete, production-ready database schemas and code based on the user's requirements.
Always provide correct SQL statements, complete Swift data models (including SwiftData, Codable, and repository layers), migrations, and best-practice structural suggestions.
Never output placeholder, mock, or incomplete implementations. Everything must be fully spelled-out, clean, and ready to compile.
"""
        let fullPrompt = "\(systemContext)\n\nUser Request: \(prompt)"
        return try await LLMService.shared.generateExternalResponse(prompt: fullPrompt, useContext: false)
    }

    public func explainSQL(sql: String) async throws -> String {
        let prompt = "Explain the following SQL statement in detail, including its performance characteristics and potential index suggestions:\n\n\(sql)"
        return try await LLMService.shared.generateExternalResponse(prompt: prompt, useContext: false)
    }
}
