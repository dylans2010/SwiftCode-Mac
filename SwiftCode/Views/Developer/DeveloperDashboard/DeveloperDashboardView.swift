import SwiftUI

struct DeveloperDashboardView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Diagnostics") {
                    NavigationLink("Verbose Logging") { VerboseLoggingView() }
                    NavigationLink("Network Inspector") { NetworkInspectorView() }
                    NavigationLink("API Inspector") { APIInspectorView() }
                    NavigationLink("Crash Debugger") { CrashDebuggerView() }
                    NavigationLink("Log Console") { LogConsoleView() }
                    NavigationLink("WebView Debugger") { WebViewDebuggerView() }
                }

                Section("Debugging") {
                    NavigationLink("GitHub API Debug") { GitHubAPIDebugView() }
                    NavigationLink("Paywall Debug") { PaywallDebugView() }
                    NavigationLink("StoreKit Debug") { StoreKitDebugView() }
                    NavigationLink("AI Model Debugger") { AIModelDebuggerView() }
                    NavigationLink("Build Pipeline Debugger") { BuildPipelineDebuggerView() }
                    NavigationLink("Extension Debugger") { ExtensionDebuggerView() }
                    NavigationLink("Deployment Debug") { DeploymentDebugView() }
                    NavigationLink("Binary Tools") { BinaryToolsViews() }
                }

                Section("Runtime Controls") {
                    NavigationLink("Feature Flags") { FeatureFlagsView() }
                    NavigationLink("Runtime Flags") { RuntimeFlagsView() }
                }

                Section("System Inspectors") {
                    NavigationLink("Memory Inspector") { MemoryInspectorView() }
                    NavigationLink("Thread Inspector") { ThreadInspectorView() }
                    NavigationLink("FileSystem Inspector") { FileSystemInspectorView() }
                    NavigationLink("Database Inspector") { DatabaseInspectorView() }
                }

                Section("Experimental Tools") {
                    NavigationLink("Performance Monitor") { PerformanceMonitorView() }
                    NavigationLink("CoreML Inspector") { CoreMLInspectorView() }
                }
            }
            .navigationTitle("Developer Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
