import SwiftUI

public struct DesignDocumentEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var designerName = ""
    @State private var figmaLink = ""

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .uiUXPlanning,
            documentID: documentID,
            specializedToolbar: {
                Button {
                    insertPalette()
                } label: {
                    Label("Design Specs", systemImage: "paintpalette")
                }
                .buttonStyle(.bordered)
            },
            specializedMetadata: {
                HStack(spacing: 20) {
                    Text("Designer:")
                        .font(.caption.bold())
                    TextField("Name", text: $designerName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)

                    Text("Figma Link:")
                        .font(.caption.bold())
                    TextField("https://...", text: $figmaLink)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                }
            },
            validationMessage: nil
        )
    }

    private func insertPalette() {
        let template = """

        ### UI/UX Color Palette Specification

        | Token Name | Hex Code | Purpose |
        | :--- | :--- | :--- |
        | `--brand-primary` | `#007AFF` | Primary button states, active tabs |
        | `--brand-success` | `#34C759` | Success checkmarks, completion banners |
        | `--text-main` | `#1C1C1E` | Primary desktop typography color |

        #### Key Typography Elements
        - **Headers:** SF Pro Display Bold, 20pt / line-height 28pt
        - **Body Text:** SF Pro Text Regular, 13pt / line-height 18pt
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
