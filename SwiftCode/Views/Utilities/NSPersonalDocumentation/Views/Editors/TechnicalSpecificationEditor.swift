import SwiftUI

public struct TechnicalSpecificationEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var reviewers = ""
    @State private var complexity = "Medium"
    @State private var systemTier = "Tier 2 (High)"
    @State private var deploymentTarget = "Cloud Native"
    @State private var expectedSLA = "99.99%"
    @State private var securityClearance = "Completed"

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .technicalSpecification,
            documentID: documentID,
            specializedToolbar: {
                Button {
                    insertOutline()
                } label: {
                    Label("Spec Outline", systemImage: "doc.text.fill")
                }
                .buttonStyle(.bordered)
            },
            specializedMetadata: {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Complexity:")
                            .font(.caption.bold())
                        Picker("", selection: $complexity) {
                            Text("High").tag("High")
                            Text("Medium").tag("Medium")
                            Text("Low").tag("Low")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)

                        Text("Reviewers:")
                            .font(.caption.bold())
                        TextField("Name, Name", text: $reviewers)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                    }

                    GridRow {
                        Text("System Tier:")
                            .font(.caption.bold())
                        Picker("", selection: $systemTier) {
                            Text("Tier 1 (Critical)").tag("Tier 1 (Critical)")
                            Text("Tier 2 (High)").tag("Tier 2 (High)")
                            Text("Tier 3 (Standard)").tag("Tier 3 (Standard)")
                        }
                        .frame(width: 180)

                        Text("Deployment Target:")
                            .font(.caption.bold())
                        Picker("", selection: $deploymentTarget) {
                            Text("Cloud Native").tag("Cloud Native")
                            Text("On-Premise").tag("On-Premise")
                            Text("Edge Computing").tag("Edge Computing")
                        }
                        .frame(width: 180)
                    }

                    GridRow {
                        Text("Expected SLA:")
                            .font(.caption.bold())
                        Picker("", selection: $expectedSLA) {
                            Text("99.9%").tag("99.9%")
                            Text("99.99%").tag("99.99%")
                            Text("99.999%").tag("99.999%")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)

                        Text("Security Clearance:")
                            .font(.caption.bold())
                        Picker("", selection: $securityClearance) {
                            Text("Required").tag("Required")
                            Text("Completed").tag("Completed")
                            Text("N/A").tag("N/A")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertOutline() {
        let template = """

        # Technical Specification: [Title]

        **Complexity:** \(complexity)
        **Reviewers:** \(reviewers)
        **System Criticality:** `\(systemTier)`
        **Deployment Model:** `\(deploymentTarget)`
        **Target Availability SLA:** `\(expectedSLA)`
        **Security Clearance:** `\(securityClearance)`

        ## 1. Executive Summary
        A short high-level overview of the proposed solution and architecture.

        ## 2. Goals & Non-Goals
        * **Goal 1:** [Specific outcome]
        * **Non-Goal 1:** [Explicitly out of scope]

        ## 3. System Architecture & Design
        Detailed flow analysis and description of APIs, databases, and microservices involved.
        - Target Topology: `\(deploymentTarget)`

        ## 4. Scaling & Performance Considerations
        Expected request throughput, bottlenecks, and database optimizations to meet `\(expectedSLA)`.

        ## 5. Security & Privacy Audit
        - Security Clearance Status: `\(securityClearance)`
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
