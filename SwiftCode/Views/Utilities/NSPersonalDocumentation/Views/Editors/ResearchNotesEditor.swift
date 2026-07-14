import SwiftUI

public struct ResearchNotesEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var sourceURL = ""
    @State private var researcherName = ""
    @State private var fieldDomain = "AI/ML"
    @State private var confidenceLevel = "Unverified"
    @State private var academicPeerReviewed = false
    @State private var importanceLevel = "Medium"

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .researchLibrary,
            documentID: documentID,
            specializedToolbar: {
                Button {
                    insertReference()
                } label: {
                    Label("Add Reference", systemImage: "books.vertical.fill")
                }
                .buttonStyle(.bordered)
            },
            specializedMetadata: {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Researcher:")
                            .font(.caption.bold())
                        TextField("Researcher Name", text: $researcherName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)

                        Text("Source URL:")
                            .font(.caption.bold())
                        TextField("https://...", text: $sourceURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)
                    }

                    GridRow {
                        Text("Field Domain:")
                            .font(.caption.bold())
                        Picker("", selection: $fieldDomain) {
                            Text("AI/ML").tag("AI/ML")
                            Text("Compilers").tag("Compilers")
                            Text("Graphics").tag("Graphics")
                            Text("Storage").tag("Storage")
                            Text("Networking").tag("Networking")
                        }
                        .frame(width: 180)

                        Toggle("Peer Reviewed", isOn: $academicPeerReviewed)
                            .help("Is this academic paper or citation peer-reviewed?")
                    }

                    GridRow {
                        Text("Confidence:")
                            .font(.caption.bold())
                        Picker("", selection: $confidenceLevel) {
                            Text("Hypothesis").tag("Hypothesis")
                            Text("Unverified").tag("Unverified")
                            Text("Verified").tag("Verified")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)

                        Text("Importance:")
                            .font(.caption.bold())
                        Picker("", selection: $importanceLevel) {
                            Text("Critical").tag("Critical")
                            Text("High").tag("High")
                            Text("Medium").tag("Medium")
                            Text("Low").tag("Low")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertReference() {
        let template = """

        ### Research Citation & Review

        * **Author/Source:** [Insert Author]
        * **Title:** [Insert Publication Title]
        * **Access URL:** [\(sourceURL)](\(sourceURL.isEmpty ? "https://example.com" : sourceURL))
        * **Researcher:** `\(researcherName.isEmpty ? "Self" : researcherName)`
        * **Field Domain:** `\(fieldDomain)`
        * **Academic Peer Reviewed:** `\(academicPeerReviewed ? "Yes" : "No")`
        * **Confidence Level:** `\(confidenceLevel)`
        * **Importance Level:** `\(importanceLevel)`

        #### Research Abstract
        Detailed technical summary of findings and takeaways of this literature or API analysis.

        #### Core Key Discoveries
        - Discovery 1
        - Discovery 2

        #### Next Steps & Hypotheses
        - Hypothesis verification planned under the `\(confidenceLevel)` scope.
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
