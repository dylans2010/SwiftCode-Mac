// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/DeveloperDashboard/DeveloperDashboardView.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: MISSING at bc28f653. Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI
import SwiftCodeUI
import SwiftCodePaywall

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
                    // No "Build Pipeline Debugger" row: Audit A marks Legacy's
                    // BuildPipelineDebuggerView COVERED-BY-REDESIGN — it was a
                    // single placeholder Text, superseded by the real CI
                    // dashboard (SwiftCodeUI `CIWindowManager`), which opens
                    // per workspace folder and has no SwiftUI entry point
                    // this dashboard can link to. W1 to wire the CI entry.
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
            .liquidGlass(style: .subtle, cornerRadius: 12)
            .navigationTitle("Developer Dashboard")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
