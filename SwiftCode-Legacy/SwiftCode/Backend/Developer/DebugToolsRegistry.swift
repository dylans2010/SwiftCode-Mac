import Foundation
import SwiftUI

public struct DebugToolInfo: Identifiable {
    public let id: String
    public let title: String
    public let icon: String
    public let description: String
    public let category: DebugCategory

    public enum DebugCategory: String, CaseIterable {
        case monitoring = "Monitoring"
        case inspector  = "Inspector"
        case diagnostics = "Diagnostics"
        case environment = "Environment"
    }
}

@MainActor
public final class DebugToolsRegistry: ObservableObject {
    public static let shared = DebugToolsRegistry()

    @Published public private(set) var tools: [DebugToolInfo] = []

    private init() {
        registerDefaultTools()
    }

    private func registerDefaultTools() {
        // Monitoring
        add(id: "log_console", title: "Log Console", icon: "terminal.fill", desc: "Live filterable app logs", category: .monitoring)
        add(id: "network_inspector", title: "Network Inspector", icon: "network", desc: "HTTP request/response logs", category: .monitoring)
        add(id: "performance_monitor", title: "Performance Monitor", icon: "gauge.with.needle.fill", desc: "Real-time CPU and Memory usage", category: .monitoring)
        add(id: "api_latency", title: "API Latency Tracker", icon: "timer", desc: "Average response times for endpoints", category: .monitoring)
        add(id: "background_tasks", title: "Background Task Monitor", icon: "hourglass.badge.plus", desc: "Scheduled and running tasks", category: .monitoring)
        add(id: "realtime_metrics", title: "Metrics Dashboard", icon: "chart.bar.xaxis", desc: "Unified dashboard of app health", category: .monitoring)

        // Inspectors
        add(id: "state_inspector", title: "State Inspector", icon: "circle.grid.3x3.fill", desc: "Visual tree of app state", category: .inspector)
        add(id: "file_system", title: "File System Explorer", icon: "folder.fill", desc: "Browse app sandbox and project files", category: .inspector)
        add(id: "cache_inspector", title: "Cache Inspector", icon: "archivebox.fill", desc: "View and clear stored caches", category: .inspector)
        add(id: "thread_inspector", title: "Thread Inspector", icon: "cpu", desc: "Active threads and stack traces", category: .inspector)
        add(id: "database_inspector", title: "Database Inspector", icon: "server.rack", desc: "Query local SQLite or CoreData", category: .inspector)

        // Diagnostics
        add(id: "crash_debugger", title: "Crash Debugger", icon: "bandage.fill", desc: "View and symbolicating crash logs", category: .diagnostics)
        add(id: "dependency_health", title: "Dependency Health", icon: "link.badge.plus", desc: "Check file/package integrity", category: .diagnostics)
        add(id: "build_diagnostics", title: "Build Diagnostics", icon: "hammer.fill", desc: "Internal build engine state", category: .diagnostics)
        add(id: "error_frequency", title: "Error Tracker", icon: "exclamationmark.octagon.fill", desc: "Grouped error analytics", category: .diagnostics)
        add(id: "memory_leaks", title: "Memory Leak Detector", icon: "drop.fill", desc: "Potential object cycle detection", category: .diagnostics)
        add(id: "permissions_checker", title: "Permissions Checker", icon: "lock.shield.fill", desc: "System permission status", category: .diagnostics)

        // Environment
        add(id: "feature_flags", title: "Feature Flags", icon: "flag.fill", desc: "Toggle internal app features", category: .environment)
        add(id: "env_switcher", title: "Environment Switcher", icon: "arrow.2.squarepath", desc: "Toggle Dev/Staging/Prod", category: .environment)
        add(id: "console_runner", title: "Console Runner", icon: "chevron.right.square.fill", desc: "Run CLI commands in sandbox", category: .environment)
        add(id: "debug_overlays", title: "Debug Overlays", icon: "squareshape.dashed.squareshape", desc: "UI overlays for layouts", category: .environment)
    }

    private func add(id: String, title: String, icon: String, desc: String, category: DebugToolInfo.DebugCategory) {
        tools.append(DebugToolInfo(id: id, title: title, icon: icon, description: desc, category: category))
    }
}
