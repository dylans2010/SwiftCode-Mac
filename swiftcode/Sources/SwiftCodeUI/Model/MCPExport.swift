// MCPExport.swift
//
// The client-side MCP manager (MCPServerManager, MCPServerConfig, MCPClient,
// MCPLoggingManager, MCPServerMetadata, MCPRemoteTool) lives in SwiftCodeMCP.
// The IDE re-exports it so app-level views can reach it through their
// SwiftCodeUI import: swiftcode-ide has no SwiftCodeMCP target dependency
// (Package.swift is coordinator-owned), and AddedMCPServersView /
// AssistComposerPopup consume the manager that way. Same pattern as
// IDECoreExport.swift / PreviewsExport.swift in this directory.
// (R-MCPSERVER, 2026-11-06. If the coordinator adds SwiftCodeMCP to the
// swiftcode-ide target dependencies instead, this file can go away.)
@_exported import SwiftCodeMCP
