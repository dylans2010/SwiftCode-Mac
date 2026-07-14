import SwiftUI

public struct TechnicalSpecificationEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var reviewers = ""
    @State private var complexity = "Medium"

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
                HStack(spacing: 20) {
                    Picker("Complexity:", selection: $complexity) {
                        Text("High").tag("High")
                        Text("Medium").tag("Medium")
                        Text("Low").tag("Low")
                    }
                    .frame(width: 150)

                    Text("Reviewers:")
                        .font(.caption.bold())
                    TextField("Name, Name", text: $reviewers)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
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

        ## 1. Executive Summary
        A short high-level overview of the proposed solution and architecture.

        ## 2. Goals & Non-Goals
        * **Goal 1:** [Specific outcome]
        * **Non-Goal 1:** [Explicitly out of scope]

        ## 3. System Architecture & Design
        Detailed flow analysis and description of APIs, databases, and microservices involved.

        ## 4. Scaling & Performance Considerations
        Expected request throughput, bottlenecks, and database optimizations.
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
