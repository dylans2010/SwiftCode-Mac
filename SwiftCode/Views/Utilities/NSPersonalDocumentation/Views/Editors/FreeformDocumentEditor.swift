import SwiftUI

public struct FreeformDocumentEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var tags = "Documentation"
    @State private var isSticky = false
    @State private var contentFocus = "Documentation"
    @State private var reviewFrequency = "Monthly"
    @State private var readTimeEstimate: Double = 5.0

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .freeformDocument,
            documentID: documentID,
            specializedToolbar: {
                Button {
                    insertTOC()
                } label: {
                    Label("Table of Contents", systemImage: "list.bullet.indent")
                }
                .buttonStyle(.bordered)
            },
            specializedMetadata: {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Tags:")
                            .font(.caption.bold())
                        TextField("comma separated tags", text: $tags)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)

                        Toggle("Sticky Note", isOn: $isSticky)
                            .help("Keep this note at the top of lists")
                    }

                    GridRow {
                        Text("Content Focus:")
                            .font(.caption.bold())
                        Picker("", selection: $contentFocus) {
                            Text("Personal").tag("Personal")
                            Text("Research").tag("Research")
                            Text("Documentation").tag("Documentation")
                            Text("Meeting").tag("Meeting")
                        }
                        .frame(width: 180)

                        Text("Review Frequency:")
                            .font(.caption.bold())
                        Picker("", selection: $reviewFrequency) {
                            Text("None").tag("None")
                            Text("Weekly").tag("Weekly")
                            Text("Monthly").tag("Monthly")
                            Text("Yearly").tag("Yearly")
                        }
                        .frame(width: 150)
                    }

                    GridRow {
                        Text("Read Time:")
                            .font(.caption.bold())
                        HStack {
                            Slider(value: $readTimeEstimate, in: 1.0...30.0, step: 1.0)
                                .frame(width: 120)
                            Text("\(Int(readTimeEstimate)) min")
                                .font(.caption.monospacedDigit())
                        }
                        .gridCellColumns(3)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertTOC() {
        let template = """

        ### Table of Contents
        1. [Overview](#overview)
        2. [Background & Objectives](#background)
        3. [Core Logic Implementation](#implementation)
        4. [Results & Analysis](#analysis)

        ---
        **Document Metadata:**
        - Content Focus: `\(contentFocus)`
        - Review Frequency: `\(reviewFrequency)`
        - Estimated Read Time: `\(Int(readTimeEstimate)) minutes`
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
