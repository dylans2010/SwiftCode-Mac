import SwiftUI

public struct ArchitectureDocumentationEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var decisionStatus = "Proposed"
    @State private var deciders = "Architecture Board"
    @State private var impactLevel = "Medium"
    @State private var techStackDomain = "Backend"
    @State private var adrVersion = "1.0"
    @State private var targetAudience = "Engineering"

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
                Button {
                    insertADR()
                } label: {
                    Label("ADR Structure", systemImage: "gavel.fill")
                }
                .buttonStyle(.bordered)
                .help("Insert Architecture Decision Record boilerplate")
            },
            specializedMetadata: {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("ADR Status:")
                            .font(.caption.bold())
                        Picker("", selection: $decisionStatus) {
                            Text("Proposed").tag("Proposed")
                            Text("Accepted").tag("Accepted")
                            Text("Rejected").tag("Rejected")
                            Text("Superseded").tag("Superseded")
                        }
                        .frame(width: 180)

                        Text("Impact Level:")
                            .font(.caption.bold())
                        Picker("", selection: $impactLevel) {
                            Text("High").tag("High")
                            Text("Medium").tag("Medium")
                            Text("Low").tag("Low")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }

                    GridRow {
                        Text("Deciders:")
                            .font(.caption.bold())
                        TextField("Names or Teams", text: $deciders)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)

                        Text("Tech Stack:")
                            .font(.caption.bold())
                        Picker("", selection: $techStackDomain) {
                            Text("Frontend").tag("Frontend")
                            Text("Backend").tag("Backend")
                            Text("Database").tag("Database")
                            Text("DevOps").tag("DevOps")
                            Text("Security").tag("Security")
                        }
                        .frame(width: 180)
                    }

                    GridRow {
                        Text("ADR Version:")
                            .font(.caption.bold())
                        TextField("e.g. 1.0", text: $adrVersion)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)

                        Text("Audience:")
                            .font(.caption.bold())
                        Picker("", selection: $targetAudience) {
                            Text("Engineering").tag("Engineering")
                            Text("Product").tag("Product")
                            Text("Security Officers").tag("Security Officers")
                        }
                        .frame(width: 180)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertADR() {
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
}
