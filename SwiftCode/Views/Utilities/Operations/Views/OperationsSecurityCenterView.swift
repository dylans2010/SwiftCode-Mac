import SwiftUI

struct OperationsSecurityCenterView: View {
    @State private var sec = SecurityManager.shared
    @State private var signing = SigningManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Security Center")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Audit development credentials, entitlements, sandbox access, and code-level secrets.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        Task {
                            await sec.runAudit()
                        }
                    } label: {
                        Label(sec.isAuditing ? "Auditing..." : "Audit Workspace", systemImage: "shield.righthalf.filled")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sec.isAuditing)
                }
                .padding(.bottom, 10)

                // Signing certificates section
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Developer Credentials")
                            .font(.headline)

                        if signing.certificates.isEmpty {
                            Text("No developer credentials discovered on local Keychain.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(signing.certificates) { cert in
                                HStack {
                                    Image(systemName: "key.fill")
                                        .foregroundStyle(.purple)
                                    VStack(alignment: .leading) {
                                        Text(cert.name)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text("Type: \(cert.type) • Expires: \(formatDate(cert.expirationDate))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(cert.isValid ? "Valid" : "Expired")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(cert.isValid ? .green : .red)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Audit findings
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Source Code Secrets Scan")
                            .font(.headline)

                        if sec.isAuditing {
                            ProgressView()
                        } else if sec.findings.isEmpty {
                            ContentUnavailableView {
                                Label("No Vulnerabilities Found", systemImage: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                            } description: {
                                Text("No hardcoded credentials, unsecure connections, or missing sandboxes detected.")
                            }
                        } else {
                            ForEach(sec.findings) { finding in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "exclamationmark.octagon.fill")
                                        .foregroundStyle(finding.severity == "Critical" ? .red : .yellow)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(finding.title)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                            Spacer()
                                            if let p = finding.filePath {
                                                Text(p)
                                                    .font(.caption2, design: .monospaced)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        Text(finding.description)
                                            .font(.caption)

                                        Text("Fix: \(finding.suggestion)")
                                            .font(.caption)
                                            .padding(6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(NSColor.controlBackgroundColor))
                                            .cornerRadius(4)
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .onAppear {
            if sec.lastAuditDate == nil {
                Task {
                    await sec.runAudit()
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        return fmt.string(from: date)
    }
}
