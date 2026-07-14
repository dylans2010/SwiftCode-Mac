import SwiftUI

public struct FreeformDocumentEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var tags = "Documentation"
    @State private var isSticky = false
    @State private var contentFocus = "Documentation"
    @State private var reviewFrequency = "Monthly"
    @State private var readTimeEstimate: Double = 5.0

    // Interactive Mindmap / Idea Outline Scratchpad
    @State private var ideaName = ""
    @State private var ideaTier = 1
    @State private var ideaScratchpad: [MindmapNode] = []

    struct MindmapNode: Identifiable, Hashable {
        let id = UUID()
        var text: String
        var tier: Int
    }

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
                HStack(spacing: 6) {
                    Button {
                        insertTOC()
                    } label: {
                        Label("Table of Contents", systemImage: "list.bullet.indent")
                    }
                    .help("Insert Table of Contents block")

                    Button {
                        insertJournalEntry()
                    } label: {
                        Label("Daily Journal", systemImage: "calendar.badge.clock")
                    }
                    .help("Insert structured engineering daily journal entry")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Focus:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $contentFocus) {
                                Text("Personal").tag("Personal")
                                Text("Research").tag("Research")
                                Text("Docs").tag("Documentation")
                                Text("Meeting").tag("Meeting")
                            }
                            .controlSize(.small)

                            Toggle("Sticky Note", isOn: $isSticky)
                                .font(.system(size: 10))
                                .controlSize(.small)
                        }

                        GridRow {
                            Text("Review:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $reviewFrequency) {
                                Text("None").tag("None")
                                Text("Weekly").tag("Weekly")
                                Text("Monthly").tag("Monthly")
                                Text("Yearly").tag("Yearly")
                            }
                            .controlSize(.small)

                            Text("Read Time:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Slider(value: $readTimeEstimate, in: 1.0...30.0, step: 1.0)
                                Text("\(Int(readTimeEstimate))m")
                                    .font(.system(size: 9, design: .monospaced))
                            }
                            .controlSize(.small)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // MINDMAP OUTLINE SCRATCHPAD
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OUTLINE / IDEA SCRATCHPAD")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                            GridRow {
                                TextField("Idea / Goal / Phase", text: $ideaName)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)

                                Picker("", selection: $ideaTier) {
                                    Text("Tier 1").tag(1)
                                    Text("Tier 2").tag(2)
                                    Text("Tier 3").tag(3)
                                }
                                .controlSize(.small)
                            }
                        }

                        Button("Insert Nested Idea") {
                            addIdea()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        // Display scratchpad nodes
                        if !ideaScratchpad.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(ideaScratchpad) { node in
                                    HStack {
                                        Text(String(repeating: "  ", count: node.tier - 1) + "• " + node.text)
                                            .font(.system(size: 9, design: .monospaced))
                                        Spacer()
                                        Button {
                                            ideaScratchpad.removeAll(where: { $0.id == node.id })
                                        } label: {
                                            Image(systemName: "xmark").font(.system(size: 7))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                Button("Inject Full Outline Block") {
                                    injectOutlineBlock()
                                }
                                .buttonStyle(.link)
                                .font(.system(size: 9, weight: .bold))
                            }
                            .padding(6)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(4)
                        }
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func addIdea() {
        let trimmed = ideaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let node = MindmapNode(text: trimmed, tier: ideaTier)
        ideaScratchpad.append(node)
        ideaName = ""
    }

    private func injectOutlineBlock() {
        var outline = "\n#### Structured Brainstorming Outline\n"
        for node in ideaScratchpad {
            let prefix = String(repeating: "  ", count: node.tier - 1) + "- "
            outline += "\(prefix)\(node.text)\n"
        }
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": outline]
        )
        ideaScratchpad.removeAll()
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

    private func insertJournalEntry() {
        let entry = """

        ### Engineering Daily Journal: \(Date().formatted(date: .abbreviated, time: .omitted))

        #### 🎯 Focus Area
        - Focus: `\(contentFocus)`
        - Reading Weight: `\(Int(readTimeEstimate)) minutes`

        #### 📝 Notes & Accomplishments
        - [ ] Completed task A.
        - [ ] Addressed edge cases and validation.

        #### ⚠️ Blocks & Challenges
        - Obstacle 1

        #### 🚀 Next Iteration Goals
        - Next objective.
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": entry]
        )
    }
}
