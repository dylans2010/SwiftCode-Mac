import SwiftUI

// MARK: - Unit Test Generator Extension View
struct UnitTestGenExtensionView: View {
    @State private var isEnabled = true
    @State private var testFramework = "xctest"
    @State private var generateMocks = true
    @State private var coverageTarget = 80

    var body: some View {
        Form {
            Section {
                Toggle("Enable Unit Test Generator", isOn: $isEnabled)
                Toggle("Generate Mock Objects", isOn: $generateMocks)
            } header: {
                Label("Unit Test Generator", systemImage: "checkmark.shield.fill")
            }
            Section {
                Picker("Test Framework", selection: $testFramework) {
                    Text("XCTest").tag("xctest")
                    Text("Swift Testing").tag("swift-testing")
                }
                .pickerStyle(.segmented)
                Stepper("Coverage Target: \(coverageTarget)%", value: $coverageTarget, in: 50...100, step: 5)
            } header: {
                Text("Configuration")
            }
            Section {
                Label("Select a function → Editor → Generate Tests", systemImage: "contextualmenu.and.cursorarrow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Usage")
            }
            Section {
                Text("Generates XCTest or Swift Testing unit tests for selected functions using AI. Includes edge cases, boundary conditions, and optional mock objects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Unit Test Generator")
        .navigationBarTitleDisplayMode(.inline)
    }
}
