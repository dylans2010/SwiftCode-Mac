import SwiftUI

public struct TestingNotesEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var coverageTarget = "85%"
    @State private var testEnvironment = "Simulator"
    @State private var testFramework = "XCTest"
    @State private var testCategory = "Unit Test"
    @State private var linkedBugID = ""
    @State private var executionStatus = "Passed"

    // Test Matrix Interactive Designer State
    @State private var tcID = "TC01"
    @State private var tcScenario = ""
    @State private var tcExpected = ""
    @State private var tcStatus = "Passed"
    @State private var addedTestCases: [TestCaseSpec] = []

    struct TestCaseSpec: Identifiable, Hashable {
        let id = UUID()
        var tcID: String
        var scenario: String
        var expected: String
        var status: String
    }

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .testingNotes,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 6) {
                    Button {
                        insertTestGrid()
                    } label: {
                        Label("Test Matrix", systemImage: "checklist")
                    }
                    .help("Insert technical QA Test Matrix checklist table")

                    Button {
                        insertDiagnosticsBlock()
                    } label: {
                        Label("Diagnostics Log", systemImage: "macpro.gen1")
                    }
                    .help("Insert diagnostic artifact references log")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Env:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $testEnvironment) {
                                Text("Simulator").tag("Simulator")
                                Text("Device").tag("Device")
                                Text("CI").tag("CI Server")
                            }
                            .controlSize(.small)

                            Text("Coverage:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("80%", text: $coverageTarget)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }

                        GridRow {
                            Text("Framework:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $testFramework) {
                                Text("XCTest").tag("XCTest")
                                Text("Playwright").tag("Playwright")
                                Text("Selenium").tag("Selenium")
                            }
                            .controlSize(.small)

                            Text("Category:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $testCategory) {
                                Text("Unit").tag("Unit Test")
                                Text("Integration").tag("Integration")
                                Text("UI/E2E").tag("UI/E2E")
                            }
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("Ticket ID:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. BUG-304", text: $linkedBugID)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)

                            Text("Status:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $executionStatus) {
                                Text("Passed").tag("Passed")
                                Text("Failed").tag("Failed")
                                Text("Blocked").tag("Blocked")
                            }
                            .controlSize(.small)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // QA TEST MATRIX BUILDER
                    VStack(alignment: .leading, spacing: 6) {
                        Text("QA TEST MATRIX EXECUTION DESIGNER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                            GridRow {
                                TextField("ID (e.g. TC03)", text: $tcID)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)

                                Picker("", selection: $tcStatus) {
                                    Text("Passed").tag("Passed")
                                    Text("Failed").tag("Failed")
                                    Text("Blocked").tag("Blocked")
                                }
                                .controlSize(.small)
                            }
                            GridRow {
                                TextField("Scenario description...", text: $tcScenario)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .gridCellColumns(2)
                            }
                            GridRow {
                                TextField("Expected Outcome...", text: $tcExpected)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .gridCellColumns(2)
                            }
                        }

                        Button("Add Test Case Spec") {
                            addTestCase()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        // Added test cases checklist list
                        if !addedTestCases.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(addedTestCases) { tc in
                                    HStack {
                                        Text(tc.tcID)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        Text(tc.scenario)
                                            .font(.system(size: 9))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(tc.status)
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(tc.status == "Passed" ? .green : .red)

                                        Button {
                                            addedTestCases.removeAll(where: { $0.id == tc.id })
                                        } label: {
                                            Image(systemName: "xmark").font(.system(size: 7))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(4)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func addTestCase() {
        let name = tcScenario.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let spec = TestCaseSpec(
            tcID: tcID.isEmpty ? "TC01" : tcID,
            scenario: name,
            expected: tcExpected.isEmpty ? "Passes validation check" : tcExpected,
            status: tcStatus
        )
        addedTestCases.append(spec)
        tcScenario = ""
        tcExpected = ""

        // Auto increment TC ID
        if let currentNum = Int(tcID.filter(\.isNumber)) {
            tcID = "TC" + String(format: "%02d", currentNum + 1)
        }
    }

    private func insertTestGrid() {
        var matrixMarkdown = "| ID | Test Scenario | Expected Result | Status |\n| :--- | :--- | :--- | :--- |\n"
        if addedTestCases.isEmpty {
            matrixMarkdown += "| TC01 | Create API Doc | Document created and launches APIDocumentationEditor | \(executionStatus) |\n| TC02 | Sidebar Category Switch | Active editor replaced entirely | \(executionStatus) |\n"
        } else {
            for tc in addedTestCases {
                matrixMarkdown += "| \(tc.tcID) | \(tc.scenario) | \(tc.expected) | \(tc.status) |\n"
            }
        }

        let template = """

        ### QA & Testing Notes Specifications

        **Target Coverage:** \(coverageTarget)
        **Testing Environment:** \(testEnvironment)
        **Automation Framework:** `\(testFramework)`
        **Test Category:** `\(testCategory)`
        **Linked Ticket:** `\(linkedBugID.isEmpty ? "None" : linkedBugID)`
        **Current Execution Status:** `\(executionStatus)`

        #### Test Case Matrix
        \(matrixMarkdown)

        #### Diagnostics & Artifacts
        - Execution Log: Verified under `\(testEnvironment)` on `\(Date().formatted(date: .numeric, time: .shortened))`
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }

    private func insertDiagnosticsBlock() {
        let diagnostics = """

        #### Diagnostic Logs and Artifacts (\(testEnvironment))
        ```javascript
        // Environment details
        const testFramework = "\(testFramework)";
        const suite = {
          category: "\(testCategory)",
          coverageTarget: "\(coverageTarget)",
          status: "PASSED"
        };
        console.log(`Diagnostics executed on ${testFramework}: SUCCESS`);
        ```
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": diagnostics]
        )
    }
}
