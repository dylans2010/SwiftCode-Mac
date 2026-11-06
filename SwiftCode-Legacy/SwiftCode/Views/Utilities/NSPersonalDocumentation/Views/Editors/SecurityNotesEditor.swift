import SwiftUI

public struct SecurityNotesEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var securitySeverity = "Critical"
    @State private var scope = "Internal"
    @State private var cvssScore: Double = 7.5
    @State private var vulnerabilityClass = "OWASP Top 10"
    @State private var complianceTarget = "SOC2"
    @State private var remediationSLA = "7 days"

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .securityNotes,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 8) {
                    Button {
                        insertThreatModel()
                    } label: {
                        Label("Threat Model", systemImage: "shield.fill")
                    }
                    .buttonStyle(.bordered)
                }
            },
            specializedMetadata: {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Severity:")
                            .font(.caption.bold())
                        Picker("", selection: $securitySeverity) {
                            Text("Critical").tag("Critical")
                            Text("High").tag("High")
                            Text("Medium").tag("Medium")
                            Text("Low").tag("Low")
                        }
                        .frame(width: 180)

                        Text("Scope:")
                            .font(.caption.bold())
                        Picker("", selection: $scope) {
                            Text("Internal").tag("Internal")
                            Text("External").tag("External")
                        }
                        .frame(width: 180)
                    }

                    GridRow {
                        Text("CVSS Base Score:")
                            .font(.caption.bold())
                        HStack {
                            Slider(value: $cvssScore, in: 0.0...10.0, step: 0.1)
                                .frame(width: 120)
                            Text(String(format: "%.1f", cvssScore))
                                .font(.caption.monospacedDigit())
                        }

                        Text("Remediation SLA:")
                            .font(.caption.bold())
                        TextField("e.g. 7 days", text: $remediationSLA)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                    }

                    GridRow {
                        Text("Vulnerability Class:")
                            .font(.caption.bold())
                        Picker("", selection: $vulnerabilityClass) {
                            Text("OWASP Top 10").tag("OWASP Top 10")
                            Text("CWE Classification").tag("CWE Classification")
                            Text("Zero-Day").tag("Zero-Day")
                        }
                        .frame(width: 180)

                        Text("Compliance Target:")
                            .font(.caption.bold())
                        Picker("", selection: $complianceTarget) {
                            Text("SOC2").tag("SOC2")
                            Text("GDPR").tag("GDPR")
                            Text("HIPAA").tag("HIPAA")
                            Text("None").tag("None")
                        }
                        .frame(width: 180)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func insertThreatModel() {
        let template = """

        ### Threat Model & Mitigation Notes

        **Severity:** \(securitySeverity) (CVSS Base Score: `\(String(format: "%.1f", cvssScore))`)
        **Review Scope:** \(scope)
        **Vulnerability Class:** `\(vulnerabilityClass)`
        **Compliance Target:** `\(complianceTarget)`
        **Remediation SLA:** `\(remediationSLA)`

        #### Potential Threat Vector
        - **Threat:** [Description of possible attack vector]
        - **Asset at Risk:** [Database, Authentication Token, etc.]

        #### Mitigation Strategy
        - **Action:** [Steps to mitigate risk, e.g. input validation, encryption at rest]
        - **Validator:** [Testing process to ensure verification]

        #### Compliance Audit Mapping
        - Target Mapping: `\(complianceTarget)` control verification criteria.
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }
}
