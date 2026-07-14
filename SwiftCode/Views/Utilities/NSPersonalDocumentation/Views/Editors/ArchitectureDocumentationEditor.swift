import SwiftUI

public struct ArchitectureDocumentationEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var decisionStatus = "Proposed"
    @State private var deciders = "Architecture Board"

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
                HStack(spacing: 20) {
                    Picker("ADR Status:", selection: $decisionStatus) {
                        Text("Proposed").tag("Proposed")
                        Text("Accepted").tag("Accepted")
                        Text("Rejected").tag("Rejected")
                        Text("Superseded").tag("Superseded")
                    }
                    .frame(width: 180)

                    Text("Deciders:")
                        .font(.caption.bold())
                    TextField("Names or Teams", text: $deciders)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
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
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
