import SwiftUI

public struct ArchitectureDocumentationEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var decisionStatus = "Proposed"
    @State private var deciders = "Architecture Board"
    @State private var impactLevel = "Medium"
    @State private var techStackDomain = "Backend"
    @State private var adrVersion = "1.0"
    @State private var targetAudience = "Engineering"

    // Consequences Interactive Matrix
    @State private var isSecurityReviewed = false
    @State private var isSlaCompliant = false
    @State private var isRollbackDrafted = false
    @State private var isScalabilityVerified = false

    // System Flow Template Variables
    @State private var flowSource = "Client"
    @State private var flowDestination = "API Gateway"
    @State private var flowAction = "Authenticate Request"

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .architectureDecisions,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 6) {
                    Button {
                        insertADR()
                    } label: {
                        Label("ADR Boilerplate", systemImage: "gavel.fill")
                    }
                    .help("Insert complete ADR structure boilerplate")

                    Button {
                        insertMermaidDiagram()
                    } label: {
                        Label("Mermaid Diagram", systemImage: "square.split.3x1")
                    }
                    .help("Insert architectural sequence diagram using Mermaid syntax")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("ADR Status:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $decisionStatus) {
                                Text("Proposed").tag("Proposed")
                                Text("Accepted").tag("Accepted")
                                Text("Rejected").tag("Rejected")
                                Text("Superseded").tag("Superseded")
                            }
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Impact:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $impactLevel) {
                                Text("High").tag("High")
                                Text("Medium").tag("Medium")
                                Text("Low").tag("Low")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Deciders:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("Board or team names", text: $deciders)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Domain:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $techStackDomain) {
                                Text("Frontend").tag("Frontend")
                                Text("Backend").tag("Backend")
                                Text("Database").tag("Database")
                                Text("DevOps").tag("DevOps")
                                Text("Security").tag("Security")
                            }
                            .controlSize(.small)

                            Text("Version:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("1.0", text: $adrVersion)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }

                        GridRow {
                            Text("Audience:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $targetAudience) {
                                Text("Engineering").tag("Engineering")
                                Text("Product").tag("Product")
                                Text("Security").tag("Security Officers")
                            }
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // Consequences & Impact Checklists
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CONSEQUENCES & COMPLIANCE MATRIX")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Security Reviewed", isOn: $isSecurityReviewed)
                            Toggle("High Availability SLA Compliant", isOn: $isSlaCompliant)
                            Toggle("Rollback Strategy Planned", isOn: $isRollbackDrafted)
                            Toggle("Scalability Risks Evaluated", isOn: $isScalabilityVerified)
                        }
                        .font(.system(size: 10))
                        .controlSize(.small)
                    }

                    Divider().padding(.vertical, 4)

                    // System Flow Diagram Blueprint Builder
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SYSTEM SEQUENCE DIAGRAM BUILDER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                            GridRow {
                                TextField("From (e.g. Client)", text: $flowSource)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                TextField("To (e.g. Gateway)", text: $flowDestination)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                            }
                            GridRow {
                                TextField("Action description", text: $flowAction)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .gridCellColumns(2)
                            }
                        }

                        Button("Insert Flow Sequence") {
                            insertFlowStep()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertFlowStep() {
        let flow = """

        ```mermaid
        sequenceDiagram
            \(flowSource)->>\(flowDestination): \(flowAction)
            Note over \(flowDestination): Process request
            \(flowDestination)-->>\(flowSource): Acknowledge
        ```
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": flow]
        )
    }

    private func insertADR() {
        var complianceSection = ""
        if isSecurityReviewed { complianceSection += "- [x] **Security Reviewed**: All potential attack vectors mitigated.\n" }
        else { complianceSection += "- [ ] Security Review Pending.\n" }

        if isSlaCompliant { complianceSection += "- [x] **HA SLA Checked**: Conforms to performance limits.\n" }
        else { complianceSection += "- [ ] SLA Performance Audit Pending.\n" }

        if isRollbackDrafted { complianceSection += "- [x] **Rollback Ready**: Rollback procedure documented in detail below.\n" }
        else { complianceSection += "- [ ] Rollback Strategy Pending.\n" }

        if isScalabilityVerified { complianceSection += "- [x] **Scalability Verified**: Core bottlenecks resolved.\n" }
        else { complianceSection += "- [ ] Scalability Review Pending.\n" }

        let template = """

        # Architectural Decision Record: [Short Title]

        **Status:** \(decisionStatus)
        **Deciders:** \(deciders)
        **Date:** \(Date().formatted(date: .abbreviated, time: .omitted))
        **ADR Version:** `v\(adrVersion)`
        **Impact Level:** `\(impactLevel)`
        **Tech Domain:** `\(techStackDomain)`
        **Target Audience:** `\(targetAudience)`

        ## Context & Problem Statement
        What is the design challenge? What circumstances led to this choice?

        ## Decision Drivers
        - Driver 1
        - Driver 2

        ## Considered Options
        1. Option A
        2. Option B

        ## Decision Outcome
        Chosen Option: **[Option Name]** because [reasoning].

        ### Consequences
        - **Good:** [Positive outcome]
        - **Bad:** [Negative impact/compromise]

        ## Consequences & Compliance Matrix
        \(complianceSection)

        ## Impact Analysis & Risk Management
        - Security Impact: [Describe security checks]
        - Operations/SLA Impact: [Deployment and scale effects]

        ## Rollback Strategy
        - How do we roll back if this decision fails?
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }

    private func insertMermaidDiagram() {
        let diagram = """

        #### System Architecture Topology Sequence
        ```mermaid
        sequenceDiagram
            Client->>API Gateway: Request Resource (Auth Bearer)
            API Gateway->>Microservice: Dispatch Context
            Microservice->>Database: Query Cache/Store
            Database-->>Microservice: Return Rows
            Microservice-->>API Gateway: Payload (JSON)
            API Gateway-->>Client: 200 OK Response
        ```
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": diagram]
        )
    }
}
