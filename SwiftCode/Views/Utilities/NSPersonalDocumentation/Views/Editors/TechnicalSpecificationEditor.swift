import SwiftUI

public struct TechnicalSpecificationEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var reviewers = ""
    @State private var complexity = "Medium"
    @State private var systemTier = "Tier 2 (High)"
    @State private var deploymentTarget = "Cloud Native"
    @State private var expectedSLA = "99.99%"
    @State private var securityClearance = "Completed"

    // RFC Goal / Non-Goal Model State
    @State private var goalText = ""
    @State private var isGoalType = true
    @State private var trackingGoals: [SpecificationGoal] = []

    struct SpecificationGoal: Identifiable, Hashable {
        let id = UUID()
        var text: String
        var isGoal: Bool
    }

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
                HStack(spacing: 6) {
                    Button {
                        insertOutline()
                    } label: {
                        Label("Spec Outline", systemImage: "doc.text.fill")
                    }
                    .help("Insert complete RFC/Technical Specification Outline")

                    Button {
                        insertScalingForm()
                    } label: {
                        Label("SLA Metrics", systemImage: "waveform.path.ecg")
                    }
                    .help("Insert scaling metrics and latency boundaries specification")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Complexity:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $complexity) {
                                Text("High").tag("High")
                                Text("Med").tag("Medium")
                                Text("Low").tag("Low")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Reviewers:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("Name, Name", text: $reviewers)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Tier:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $systemTier) {
                                Text("Tier 1").tag("Tier 1 (Critical)")
                                Text("Tier 2").tag("Tier 2 (High)")
                                Text("Tier 3").tag("Tier 3 (Standard)")
                            }
                            .controlSize(.small)

                            Text("Deploy:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $deploymentTarget) {
                                Text("Cloud").tag("Cloud Native")
                                Text("On-Prem").tag("On-Premise")
                                Text("Edge").tag("Edge Computing")
                            }
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("SLA Target:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $expectedSLA) {
                                Text("99.9%").tag("99.9%")
                                Text("99.99%").tag("99.99%")
                                Text("99.999%").tag("99.999%")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Security:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $securityClearance) {
                                Text("Req").tag("Required")
                                Text("Done").tag("Completed")
                                Text("N/A").tag("N/A")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // RFC GOALS & NON-GOALS PLANNER
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RFC GOAL / NON-GOAL PLANNER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                            GridRow {
                                TextField("Scope item description...", text: $goalText)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)

                                Picker("", selection: $isGoalType) {
                                    Text("Goal").tag(true)
                                    Text("Non").tag(false)
                                }
                                .controlSize(.small)
                            }
                        }

                        Button("Add Scope Item") {
                            addGoal()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        // Goal tracking count badge
                        if !trackingGoals.isEmpty {
                            HStack {
                                Text("Goals: \(trackingGoals.filter({ $0.isGoal }).count)")
                                    .foregroundStyle(.green)
                                Text("•")
                                Text("Non-Goals: \(trackingGoals.filter({ !$0.isGoal }).count)")
                                    .foregroundStyle(.red)
                            }
                            .font(.system(size: 10, weight: .bold))
                        }
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func addGoal() {
        let trimmed = goalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let spec = SpecificationGoal(text: trimmed, isGoal: isGoalType)
        trackingGoals.append(spec)
        goalText = ""
    }

    private func insertOutline() {
        var goalsMarkdown = ""
        let goals = trackingGoals.filter { $0.isGoal }
        let nonGoals = trackingGoals.filter { !$0.isGoal }

        if !goals.isEmpty {
            goalsMarkdown += "\n#### Core Project Goals:\n"
            for g in goals { goalsMarkdown += "- [x] **Goal**: \(g.text)\n" }
        } else {
            goalsMarkdown += "\n#### Core Project Goals:\n- [ ] **Goal 1**: Achieve highly reliable execution profiles.\n"
        }

        if !nonGoals.isEmpty {
            goalsMarkdown += "\n#### Explicit Non-Goals (Out of Scope):\n"
            for ng in nonGoals { goalsMarkdown += "- [ ] *Non-Goal*: \(ng.text)\n" }
        } else {
            goalsMarkdown += "\n#### Explicit Non-Goals (Out of Scope):\n- [ ] *Non-Goal*: Resolving legacy architectural constraints.\n"
        }

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
        \(goalsMarkdown)

        ## 3. System Architecture & Design
        Detailed flow analysis and description of APIs, databases, and microservices involved.
        - Target Topology: `\(deploymentTarget)`

        ## 4. Scaling & Performance Considerations
        Expected request throughput, bottlenecks, and database optimizations to meet `\(expectedSLA)`.

        ## 5. Security & Privacy Audit
        - Security Clearance Status: ``\(securityClearance)``
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }

    private func insertScalingForm() {
        let metrics = """

        #### SLA Availability and Performance Bounds (\(expectedSLA))
        - **Target Availability**: `\(expectedSLA)` (Maximum downtime of ~\(expectedSLA == "99.999%" ? "5.26 minutes/year" : "52.6 minutes/year"))
        - **Read Latency P99**: `< 100ms`
        - **Write Latency P99**: `< 250ms`
        - **System Scaling Model**: `\(deploymentTarget)` horizontal scaling topology.
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": metrics]
        )
    }
}
