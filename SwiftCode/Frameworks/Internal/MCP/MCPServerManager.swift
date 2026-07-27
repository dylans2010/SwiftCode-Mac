import Foundation
import os
import Observation

private let logger = Logger(subsystem: "com.swiftcode.mcp", category: "MCPServerManager")

@Observable
@MainActor
public final class MCPServerManager: Sendable {
    public static let shared = MCPServerManager()

    public private(set) var servers: [MCPServer] = []

    // In-memory active clients mapped by Server ID
    private var activeClients: [UUID: MCPClient] = [:]

    private let saveURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = appSupport.appendingPathComponent("SwiftCode", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("mcp_servers.json")
    }()

    private init() {
        loadServers()
    }

    // MARK: - Server Persistence

    private func loadServers() {
        logger.log("Restoring configured MCP servers from \(self.saveURL.path)...")
        do {
            guard FileManager.default.fileExists(atPath: saveURL.path) else {
                logger.log("No previous MCP server configuration file found. Starting empty.")
                return
            }
            let data = try Data(contentsOf: saveURL)
            var restored = try JSONDecoder().decode([MCPServer].self, from: data)
            // Ensure runtime status is disconnected initially
            for idx in restored.indices {
                restored[idx].status = .disconnected
                restored[idx].lastError = nil
            }
            self.servers = restored
            logger.log("Successfully restored \(restored.count) MCP servers.")
        } catch {
            logger.error("Failed to restore MCP servers: \(error.localizedDescription)")
        }
    }

    public func saveServers() {
        do {
            let data = try JSONEncoder().encode(self.servers)
            try data.write(to: saveURL, options: .atomic)
            logger.log("MCP servers saved successfully.")
        } catch {
            logger.error("Failed to save MCP servers: \(error.localizedDescription)")
        }
    }

    // MARK: - Server Configuration Management

    public func addServer(_ server: MCPServer, secretKey: String? = nil) {
        servers.append(server)
        if let key = secretKey {
            saveSecret(key, for: server.id)
        }
        saveServers()
    }

    public func updateServer(_ updated: MCPServer, secretKey: String? = nil) {
        if let idx = servers.firstIndex(where: { $0.id == updated.id }) {
            servers[idx] = updated
            if let key = secretKey {
                saveSecret(key, for: updated.id)
            }
            saveServers()
        }
    }

    public func deleteServer(_ server: MCPServer) {
        disconnect(server: server)
        servers.removeAll { $0.id == server.id }
        deleteSecret(for: server.id)
        saveServers()
    }

    // MARK: - Keychain Secret Helpers

    private func saveSecret(_ secret: String, for serverID: UUID) {
        let key = "mcp-server-key-\(serverID.uuidString)"
        KeychainService.shared.set(secret, forKey: key)
    }

    public func getSecret(for serverID: UUID) -> String? {
        let key = "mcp-server-key-\(serverID.uuidString)"
        return KeychainService.shared.get(forKey: key)
    }

    private func deleteSecret(for serverID: UUID) {
        let key = "mcp-server-key-\(serverID.uuidString)"
        KeychainService.shared.delete(forKey: key)
    }

    // MARK: - Lifecycle Operations

    public func connect(server: MCPServer) async throws {
        guard let idx = servers.firstIndex(where: { $0.id == server.id }) else {
            throw MCPError.invalidConfiguration("Server is not registered in manager")
        }

        servers[idx].status = .connecting
        servers[idx].lastError = nil
        MCPLoggingManager.shared.log(severity: .info, serverName: server.displayName, message: "Manager initiating connection attempt...")

        let client = MCPClient(server: servers[idx])
        activeClients[server.id] = client

        do {
            let metadata = try await client.connect()

            // Successfully connected! Update state
            servers[idx].status = .connected
            servers[idx].capabilities = ["tools"] // Statically negotiated for tool use

            // Automatically trigger tool discovery right after connection
            let toolsList = try await client.listTools()
            servers[idx].tools = toolsList
            servers[idx].toolCount = toolsList.count
            servers[idx].lastRefresh = Date()
            servers[idx].lastError = nil

            logger.log("MCP Server '\(server.displayName)' status updated to Connected with \(toolsList.count) tools.")
            MCPLoggingManager.shared.log(severity: .info, serverName: server.displayName, message: "Manager marked server Connected successfully with \(toolsList.count) tools.")
        } catch {
            servers[idx].status = .failed
            servers[idx].lastError = error.localizedDescription
            activeClients.removeValue(forKey: server.id)
            logger.error("Failed to connect MCP server '\(server.displayName)': \(error.localizedDescription)")
            MCPLoggingManager.shared.log(severity: .error, serverName: server.displayName, message: "Manager connection failed: \(error.localizedDescription)")
            throw error
        }
    }

    public func disconnect(server: MCPServer) {
        MCPLoggingManager.shared.log(severity: .info, serverName: server.displayName, message: "Manager disconnecting server...")
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx].status = .disconnected
            servers[idx].lastError = nil
            servers[idx].tools = []
            servers[idx].toolCount = 0
        }

        if let client = activeClients.removeValue(forKey: server.id) {
            client.disconnect()
        }
        logger.log("MCP Server '\(server.displayName)' disconnected.")
        MCPLoggingManager.shared.log(severity: .info, serverName: server.displayName, message: "Manager successfully disconnected server.")
    }

    public func refreshTools(server: MCPServer) async throws {
        guard let client = activeClients[server.id],
              let idx = servers.firstIndex(where: { $0.id == server.id }) else {
            MCPLoggingManager.shared.log(severity: .error, serverName: server.displayName, message: "Failed to refresh tools: server is not connected.")
            throw MCPError.connectionFailed("Server '\(server.displayName)' is not actively connected.")
        }

        MCPLoggingManager.shared.log(severity: .info, serverName: server.displayName, message: "Manager refreshing available tools...")
        do {
            let toolsList = try await client.listTools()
            servers[idx].tools = toolsList
            servers[idx].toolCount = toolsList.count
            servers[idx].lastRefresh = Date()
            servers[idx].lastError = nil
            logger.log("Refreshed tools for '\(server.displayName)': discovered \(toolsList.count) tools.")
            MCPLoggingManager.shared.log(severity: .info, serverName: server.displayName, message: "Manager refreshed tools successfully. Discovered \(toolsList.count) tools.")
        } catch {
            servers[idx].lastError = "Refresh tools failed: \(error.localizedDescription)"
            logger.error("Failed to refresh tools for '\(server.displayName)': \(error.localizedDescription)")
            MCPLoggingManager.shared.log(severity: .error, serverName: server.displayName, message: "Manager refresh tools failed: \(error.localizedDescription)")
            throw error
        }
    }

    public func callTool(serverID: UUID, name: String, arguments: [String: JSONValue]) async throws -> MCPExecutionResponse {
        guard let client = activeClients[serverID] else {
            throw MCPError.connectionFailed("Server is not actively connected.")
        }
        return try await client.callTool(name: name, arguments: arguments)
    }

    // MARK: - Handshake Test connection without saving

    public func testConnection(config: MCPServer, secretKey: String? = nil) async throws -> (MCPServerMetadata, [MCPTool]) {
        logger.log("Testing connection to temporary server config '\(config.displayName)'...")

        // Temporarily store the secret in keychain if provided
        let tempKey = "mcp-server-key-\(config.id.uuidString)"
        if let key = secretKey {
            KeychainService.shared.set(key, forKey: tempKey)
        }

        let client = MCPClient(server: config)

        defer {
            client.disconnect()
            if secretKey != nil {
                KeychainService.shared.delete(forKey: tempKey)
            }
        }

        let metadata = try await client.connect()
        let tools = try await client.listTools()

        logger.log("Test connection succeeded for '\(config.displayName)': \(tools.count) tools found.")
        return (metadata, tools)
    }
}
