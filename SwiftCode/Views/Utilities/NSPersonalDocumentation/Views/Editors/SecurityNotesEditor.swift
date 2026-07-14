import SwiftUI

public struct SecurityNotesEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var securitySeverity = "Critical"
    @State private var scope = "Internal"
    @State private var cvssScore: Double = 7.5
    @State private var vulnerabilityClass = "OWASP Top 10"
    @State private var complianceTarget = "SOC2"
    @State private var remediationSLA = "7 days"

    // CVSS Metrics States
    @State private var metricAttackVector = "Network"
    @State private var metricComplexity = "Low"
    @State private var metricConfidentiality = "High"

    private var calculatedSeverity: String {
        if cvssScore >= 9.0 { return "Critical" }
        if cvssScore >= 7.0 { return "High" }
        if cvssScore >= 4.0 { return "Medium" }
        return "Low"
    }

    private var cvssVectorString: String {
        let av = metricAttackVector == "Network" ? "N" : (metricAttackVector == "Adjacent" ? "A" : "L")
        let ac = metricComplexity == "Low" ? "L" : "H"
        let c = metricConfidentiality == "High" ? "H" : "L"
        return "CVSS:3.1/AV:\(av)/AC:\(ac)/C:\(c)/I:H/A:H"
    }

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
                HStack(spacing: 6) {
                    Button {
                        insertThreatModel()
                    } label: {
                        Label("Threat Model", systemImage: "shield.fill")
                    }
                    .help("Insert Threat Model and Mitigation Notes spec")

                    Button {
                        insertCvssAudit()
                    } label: {
                        Label("CVSS Vector", systemImage: "chart.bar.doc.horizontal")
                    }
                    .help("Insert detailed CVSS v3.1 metrics audit block")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    // CVSS Score Visual HUD
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("DYNAMIC SEVERITY HUD")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(calculatedSeverity) (\(String(format: "%.1f", cvssScore)))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(severityColor)
                        }

                        ProgressView(value: cvssScore, total: 10.0)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                            .tint(severityColor)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Severity:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $securitySeverity) {
                                Text("Critical").tag("Critical")
                                Text("High").tag("High")
                                Text("Med").tag("Medium")
                            }
                            .controlSize(.small)

                            Text("Scope:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $scope) {
                                Text("Internal").tag("Internal")
                                Text("External").tag("External")
                            }
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("SLA:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("7 days", text: $remediationSLA)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)

                            Text("Compliance:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $complianceTarget) {
                                Text("SOC2").tag("SOC2")
                                Text("GDPR").tag("GDPR")
                                Text("None").tag("None")
                            }
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("Vulnerability:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $vulnerabilityClass) {
                                Text("OWASP").tag("OWASP Top 10")
                                Text("CWE").tag("CWE Classification")
                                Text("Zero-Day").tag("Zero-Day")
                            }
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // CVSS CALCULATOR
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CVSS v3.1 METRICS CALCULATOR")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                            GridRow {
                                Text("Attack Vector:")
                                    .font(.system(size: 9))
                                Picker("", selection: $metricAttackVector) {
                                    Text("Network").tag("Network")
                                    Text("Adjacent").tag("Adjacent")
                                    Text("Local").tag("Local")
                                }
                                .controlSize(.small)
                            }
                            GridRow {
                                Text("Complexity:")
                                    .font(.system(size: 9))
                                Picker("", selection: $metricComplexity) {
                                    Text("Low").tag("Low")
                                    Text("High").tag("High")
                                }
                                .pickerStyle(.segmented)
                                .controlSize(.small)
                            }
                            GridRow {
                                Text("Confidentiality:")
                                    .font(.system(size: 9))
                                Picker("", selection: $metricConfidentiality) {
                                    Text("High").tag("High")
                                    Text("Low").tag("Low")
                                }
                                .pickerStyle(.segmented)
                                .controlSize(.small)
                            }
                            GridRow {
                                Text("Base Score:")
                                    .font(.system(size: 9))
                                HStack(spacing: 4) {
                                    Slider(value: $cvssScore, in: 0.0...10.0, step: 0.1)
                                    Text(String(format: "%.1f", cvssScore))
                                        .font(.system(size: 9, design: .monospaced))
                                }
                            }
                        }

                        Text("Vector: \(cvssVectorString)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            },
            validationMessage: nil
        )
    }

    private var severityColor: Color {
        switch calculatedSeverity {
        case "Critical": return .red
        case "High": return .orange
        case "Medium": return .yellow
        default: return .green
        }
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

    private func insertCvssAudit() {
        let audit = """

        #### CVSS v3.1 Severity Audit Specs
        - **CVSS Score**: `\(String(format: "%.1f", cvssScore))` (\(calculatedSeverity))
        - **Vector String**: `\(cvssVectorString)`
        - **Attack Vector (AV)**: `\(metricAttackVector)`
        - **Attack Complexity (AC)**: `\(metricComplexity)`
        - **Confidentiality Impact (C)**: `\(metricConfidentiality)`
        - **Remediation SLA Target**: `\(remediationSLA)`
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": audit]
        )
    }
}
