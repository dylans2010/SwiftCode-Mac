import SwiftUI

public struct ResearchNotesEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var sourceURL = ""
    @State private var researcherName = ""
    @State private var fieldDomain = "AI/ML"
    @State private var confidenceLevel = "Unverified"
    @State private var academicPeerReviewed = false
    @State private var importanceLevel = "Medium"

    // Citation builder state variables
    @State private var citeAuthors = ""
    @State private var citeTitle = ""
    @State private var citeJournal = ""
    @State private var citeYear = ""
    @State private var citationFormat = "APA"

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    private var validationMessage: String? {
        if !sourceURL.isEmpty && !sourceURL.hasPrefix("http://") && !sourceURL.hasPrefix("https://") {
            return "URL must begin with http:// or https://"
        }
        return nil
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .researchLibrary,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 6) {
                    Button {
                        insertReference()
                    } label: {
                        Label("Research Citation", systemImage: "books.vertical.fill")
                    }
                    .help("Insert full technical research review and bibliography citation")

                    Button {
                        insertHypothesis()
                    } label: {
                        Label("Hypothesis", systemImage: "sparkles")
                    }
                    .help("Insert hypothesis modeling and testing strategy")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Researcher:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("Lead", text: $researcherName)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)

                            Text("Domain:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $fieldDomain) {
                                Text("AI/ML").tag("AI/ML")
                                Text("Compilers").tag("Compilers")
                                Text("Storage").tag("Storage")
                            }
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("Source URL:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("https://...", text: $sourceURL)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Confidence:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $confidenceLevel) {
                                Text("Hypothesis").tag("Hypothesis")
                                Text("Unverified").tag("Unverified")
                                Text("Verified").tag("Verified")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }

                        GridRow {
                            Text("Importance:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $importanceLevel) {
                                Text("Crit").tag("Critical")
                                Text("High").tag("High")
                                Text("Med").tag("Medium")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)

                            Toggle("Peer-Rev", isOn: $academicPeerReviewed)
                                .font(.system(size: 10))
                                .controlSize(.small)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // BIBLIOGRAPHIC CITATION BUILDER
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BIBLIOGRAPHIC CITATION GENERATOR")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                            GridRow {
                                TextField("Authors (e.g. Smith, J.)", text: $citeAuthors)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                TextField("Year", text: $citeYear)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                            }
                            GridRow {
                                TextField("Publication Title", text: $citeTitle)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .gridCellColumns(2)
                            }
                            GridRow {
                                TextField("Journal / Publisher", text: $citeJournal)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .gridCellColumns(2)
                            }
                        }

                        Picker("Format", selection: $citationFormat) {
                            Text("APA").tag("APA")
                            Text("MLA").tag("MLA")
                            Text("BibTeX").tag("BibTeX")
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)

                        Button("Insert Generated Citation") {
                            insertCiteBlock()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            },
            validationMessage: validationMessage
        )
    }

    private func insertCiteBlock() {
        let auth = citeAuthors.isEmpty ? "Unknown" : citeAuthors
        let yr = citeYear.isEmpty ? "n.d." : citeYear
        let title = citeTitle.isEmpty ? "Title of Publication" : citeTitle
        let journal = citeJournal.isEmpty ? "Publisher" : citeJournal

        let formatted: String
        switch citationFormat {
        case "APA":
            formatted = "> \(auth) (\(yr)). *\(title)*. \(journal)."
        case "MLA":
            formatted = "> \(auth). \"\(title).\" *\(journal)*, \(yr)."
        default:
            // BibTeX
            let key = (auth.split(separator: " ").first ?? "key") + yr
            formatted = """
            ```bibtex
            @article{\(key.lowercased()),
              author = {\(auth)},
              title = {\(title)},
              journal = {\(journal)},
              year = {\(yr)}
            }
            ```
            """
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": "\n#### Academic Citation (\(citationFormat))\n" + formatted]
        )
        citeAuthors = ""
        citeTitle = ""
        citeJournal = ""
        citeYear = ""
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

    private func insertHypothesis() {
        let hypothesis = """

        ### Research Hypothesis and Testing Strategy

        #### 🔬 Core Hypothesis
        Given the analysis in domain `\(fieldDomain)`, we hypothesize that [system modification] will yield [performance or quality gain] because [justification].

        #### 🧪 Experimental Setup
        1. **Baseline**: Current system execution statistics.
        2. **Variable**: Apply modification under `\(confidenceLevel)` conditions.
        3. **Metrics**: Latency bounds, memory footprint, and thread contention rates.
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": hypothesis]
        )
    }
}
