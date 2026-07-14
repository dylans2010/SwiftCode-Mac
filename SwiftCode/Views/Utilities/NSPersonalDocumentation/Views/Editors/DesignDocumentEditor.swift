import SwiftUI

public struct DesignDocumentEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var designerName = ""
    @State private var figmaLink = ""
    @State private var platformScope = "macOS"
    @State private var uiKitFramework = "SwiftUI"
    @State private var reviewStatus = "Draft"
    @State private var targetCompletionDate = ""

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
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Designer:")
                            .font(.caption.bold())
                        TextField("Name", text: $designerName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)

                        Text("Platform Scope:")
                            .font(.caption.bold())
                        Picker("", selection: $platformScope) {
                            Text("iOS").tag("iOS")
                            Text("macOS").tag("macOS")
                            Text("Web").tag("Web")
                            Text("Cross").tag("Cross-Platform")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }

                    GridRow {
                        Text("Figma Link:")
                            .font(.caption.bold())
                        TextField("https://...", text: $figmaLink)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)

                        Text("UI kit / Framework:")
                            .font(.caption.bold())
                        Picker("", selection: $uiKitFramework) {
                            Text("SwiftUI").tag("SwiftUI")
                            Text("AppKit").tag("AppKit")
                            Text("UIKit").tag("UIKit")
                            Text("Web Components").tag("Web Components")
                        }
                        .frame(width: 180)
                    }

                    GridRow {
                        Text("Review Status:")
                            .font(.caption.bold())
                        Picker("", selection: $reviewStatus) {
                            Text("Draft").tag("Draft")
                            Text("In Review").tag("In Review")
                            Text("Approved").tag("Approved")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)

                        Text("Target Date:")
                            .font(.caption.bold())
                        TextField("YYYY-MM-DD", text: $targetCompletionDate)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertPalette() {
        let template = """

        ### UI/UX Color Palette Specification

        **Platform Scope:** `\(platformScope)`
        **Framework Target:** `\(uiKitFramework)`
        **Review Status:** `\(reviewStatus)`
        **Lead Designer:** \(designerName.isEmpty ? "N/A" : designerName)
        **Figma Assets:** [Figma Design Link](\(figmaLink.isEmpty ? "https://figma.com" : figmaLink))
        **Target Date:** `\(targetCompletionDate.isEmpty ? "N/A" : targetCompletionDate)`

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
