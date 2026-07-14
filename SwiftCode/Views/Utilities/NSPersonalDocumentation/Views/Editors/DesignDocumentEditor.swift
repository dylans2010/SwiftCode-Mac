import SwiftUI

public struct DesignDocumentEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var designerName = ""
    @State private var figmaLink = "https://figma.com/file/sample"
    @State private var platformScope = "macOS"
    @State private var uiKitFramework = "SwiftUI"
    @State private var reviewStatus = "Draft"
    @State private var targetCompletionDate = ""

    // Color Token Interactive Generator
    @State private var selectedColor = Color.blue
    @State private var tokenName = "brand-primary"
    @State private var tokenPurpose = "Accent buttons"
    @State private var addedTokens: [ColorToken] = []

    struct ColorToken: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var hex: String
        var purpose: String
        var color: Color
    }

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    private var validationMessage: String? {
        if !figmaLink.isEmpty && !figmaLink.contains("figma.com") {
            return "Figma link must be a valid url containing 'figma.com'"
        }
        return nil
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .uiUXPlanning,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 6) {
                    Button {
                        insertPalette()
                    } label: {
                        Label("Palette Specs", systemImage: "paintpalette")
                    }
                    .help("Insert visual palette and design assets specification")

                    Button {
                        insertGridSystem()
                    } label: {
                        Label("Grid Specs", systemImage: "squareshape.split.3x3")
                    }
                    .help("Insert layout grid specifications table")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Designer:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("Lead designer", text: $designerName)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Figma:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("figma.com url", text: $figmaLink)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Platform:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $platformScope) {
                                Text("iOS").tag("iOS")
                                Text("macOS").tag("macOS")
                                Text("Web").tag("Web")
                                Text("Cross").tag("Cross")
                            }
                            .controlSize(.small)

                            Text("Framework:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $uiKitFramework) {
                                Text("SwiftUI").tag("SwiftUI")
                                Text("AppKit").tag("AppKit")
                                Text("UIKit").tag("UIKit")
                            }
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("Status:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $reviewStatus) {
                                Text("Draft").tag("Draft")
                                Text("In Review").tag("In Review")
                                Text("Approved").tag("Approved")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Due Date:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("YYYY-MM-DD", text: $targetCompletionDate)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .gridCellColumns(3)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // COLOR TOKEN GENERATOR
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COLOR PALETTE DESIGN SYSTEM")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                            GridRow {
                                TextField("Token name", text: $tokenName)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)

                                ColorPicker("", selection: $selectedColor)
                                    .controlSize(.small)
                            }
                            GridRow {
                                TextField("Purpose / Use", text: $tokenPurpose)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .gridCellColumns(2)
                            }
                        }

                        Button("Add Color Token") {
                            addToken()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        // Previewing added tokens
                        if !addedTokens.isEmpty {
                            FlowLayout(spacing: 4) {
                                ForEach(addedTokens) { tok in
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(tok.color)
                                            .frame(width: 8, height: 8)
                                        Text(tok.name)
                                            .font(.system(size: 9, weight: .semibold))
                                        Button {
                                            addedTokens.removeAll(where: { $0.id == tok.id })
                                        } label: {
                                            Image(systemName: "xmark").font(.system(size: 7))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            },
            validationMessage: validationMessage
        )
    }

    private func addToken() {
        let name = tokenName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        // Get hex representation
        let nsColor = NSColor(selectedColor)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        let hexStr = String(format: "#%02X%02X%02X", r, g, b)

        let tok = ColorToken(
            name: name,
            hex: hexStr,
            purpose: tokenPurpose.isEmpty ? "Theme Accent" : tokenPurpose,
            color: selectedColor
        )
        addedTokens.append(tok)
        tokenName = ""
        tokenPurpose = ""
    }

    private func insertPalette() {
        var tokenMarkdown = "| Token Name | Hex Code | Purpose |\n| :--- | :--- | :--- |\n"
        if addedTokens.isEmpty {
            tokenMarkdown += "| `--brand-primary` | `#007AFF` | Primary button states, active tabs |\n| `--brand-success` | `#34C759` | Success checkmarks |\n"
        } else {
            for tok in addedTokens {
                tokenMarkdown += "| `--\(tok.name)` | `\(tok.hex)` | \(tok.purpose) |\n"
            }
        }

        let template = """

        ### UI/UX Color Palette Specification

        **Platform Scope:** `\(platformScope)`
        **Framework Target:** `\(uiKitFramework)`
        **Review Status:** `\(reviewStatus)`
        **Lead Designer:** \(designerName.isEmpty ? "N/A" : designerName)
        **Figma Assets:** [Figma Design Link](\(figmaLink.isEmpty ? "https://figma.com" : figmaLink))
        **Target Date:** `\(targetCompletionDate.isEmpty ? "N/A" : targetCompletionDate)`

        \(tokenMarkdown)

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

    private func insertGridSystem() {
        let grid = """

        #### Interface Layout Grid Specifications (\(platformScope))
        | Layout Region | Column Count | Gutter Width | Side Margins | Max Constraint |
        | :--- | :--- | :--- | :--- | :--- |
        | Desktop Default | 12 columns | 16pt | 24pt | 1200pt |
        | Tablet Portrait | 8 columns | 12pt | 16pt | 800pt |
        | Handheld Compact | 4 columns | 8pt | 12pt | 480pt |
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": grid]
        )
    }
}
