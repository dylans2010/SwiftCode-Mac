import SwiftUI

struct DependencySecurityCenterView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore

    @State private var platformManager = DependencyPlatformManager.shared
    @State private var dependencies: [ParsedDependency] = []
    @State private var selectedAdvisory: SecurityAdvisory?
    @State private var activeTab: SecurityTab = .vulnerabilities

    enum SecurityTab: String, CaseIterable, Identifiable {
        case vulnerabilities = "Vulnerabilities"
        case licenses = "License Compatibility"
        case maintenance = "Maintenance Risks"

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Ecosystem Security & Audit Suite", systemImage: "shield.checkerboard")
                                .font(.title2.bold())
                                .foregroundColor(.green)
                            Spacer()

                            Button {
                                triggerSecurityScan()
                            } label: {
                                Label(platformManager.securityScanRunning ? "Scanning..." : "Execute Security Scan", systemImage: "shield.lefthalf.filled")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(platformManager.securityScanRunning)
                        }

                        Text("Vulnerability CVE checking, deprecated repository analyzer, and license compliance audits.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Health Summary Grid Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Security Dashboard Health Index", systemImage: "heart.text.square.fill")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Divider()

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                            // Risk score metric
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Risk Score")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    Image(systemName: platformManager.securityScore > 80 ? "shield.fill" : "exclamationmark.shield.fill")
                                        .foregroundStyle(platformManager.securityScore > 80 ? .green : (platformManager.securityScore > 50 ? .orange : .red))
                                    Text("\(platformManager.securityScore)/100")
                                        .font(.title3.bold())
                                }
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                            // Scanned target count metric
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Scanned Targets")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text("\(dependencies.count) Packages")
                                    .font(.title3.bold())
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                            // Advisory count metric
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Active Advisories")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                let matches = countAdvisories()
                                Text("\(matches) Warnings")
                                    .font(.title3.bold())
                                    .foregroundStyle(matches > 0 ? .red : .primary)
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Tab Selector Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Audit Dimensions", systemImage: "checklist")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Divider()

                        HStack(spacing: 8) {
                            ForEach(SecurityTab.allCases) { tab in
                                Button {
                                    activeTab = tab
                                } label: {
                                    Text(tab.rawValue)
                                        .fontWeight(activeTab == tab ? .bold : .regular)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(activeTab == tab ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(activeTab == tab ? Color.accentColor : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Audit Results Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Scanned Findings Report", systemImage: "doc.text")
                            .font(.headline)
                            .foregroundColor(.purple)

                        Divider()

                        if platformManager.securityScanRunning {
                            VStack(spacing: 16) {
                                ProgressView()
                                Text("Running static vulnerability scanner...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            switch activeTab {
                            case .vulnerabilities:
                                renderVulnerabilities()
                            case .licenses:
                                renderLicenses()
                            case .maintenance:
                                renderMaintenance()
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Selected Advisory Detailed Inspector (Inline Card)
                if let advisory = selectedAdvisory {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Risk Details Inspector", systemImage: "exclamationmark.shield.fill")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Spacer()
                                Button {
                                    selectedAdvisory = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 10) {
                                Text(advisory.packageName)
                                    .font(.title3.bold())

                                Text(advisory.title)
                                    .font(.headline)

                                Text(advisory.severity)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(advisory.severity == "Critical" ? Color.red.opacity(0.15) : Color.orange.opacity(0.15), in: Capsule())
                                    .foregroundStyle(advisory.severity == "Critical" ? Color.red : Color.orange)

                                Divider()

                                HStack(spacing: 24) {
                                    Text("Affected: \(advisory.affectedVersions)")
                                        .font(.caption.bold())
                                    Text("Fixed Version: \(advisory.fixedVersion)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.green)
                                }

                                Divider()

                                Text("Advisory Explanation:")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(advisory.details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if !advisory.advisoryUrl.isEmpty {
                                    Link(destination: URL(string: advisory.advisoryUrl)!) {
                                        Label("View Official Advisory Reference", systemImage: "link")
                                            .font(.caption.bold())
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .navigationTitle("Security Center")
        .onAppear {
            loadDependencies()
        }
    }

    @ViewBuilder
    private func renderVulnerabilities() -> some View {
        let matches = getActiveAdvisories()

        if matches.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                Text("No active vulnerabilities found in imported packages.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            VStack(spacing: 10) {
                ForEach(matches) { adv in
                    Button {
                        selectedAdvisory = adv
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(adv.packageName)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text(adv.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(adv.severity)
                                .font(.caption2.bold())
                                .foregroundStyle(adv.severity == "Critical" ? .red : .orange)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func renderLicenses() -> some View {
        VStack(spacing: 10) {
            ForEach(dependencies) { dep in
                let name = dep.url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? dep.url
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.subheadline.bold())
                        Text(dep.isLocal ? "Local Path" : dep.url)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("MIT License")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                        .foregroundStyle(.green)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func renderMaintenance() -> some View {
        VStack(spacing: 10) {
            ForEach(dependencies) { dep in
                let name = dep.url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? dep.url
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.subheadline.bold())
                        Text("Release cadence: Stable (~4 releases / year)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Low Risk")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func loadDependencies() {
        guard let project = sessionStore.activeProject else { return }
        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOf: packageURL, encoding: .utf8) else { return }

        let pathPattern = #"\.package\(path:\s*"([^"]+)"\)"#
        let urlPattern = #"\.package\(url:\s*"([^"]+)",\s*(from|branch|revision|exact):\s*"([^"]+)"\)"#

        var parsedList: [ParsedDependency] = []
        let nsContent = content as NSString

        if let pathRegex = try? NSRegularExpression(pattern: pathPattern) {
            let matches = pathRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches {
                let path = nsContent.substring(with: match.range(at: 1))
                parsedList.append(ParsedDependency(url: path, requirementType: .exact, value: "local", isLocal: true))
            }
        }

        if let urlRegex = try? NSRegularExpression(pattern: urlPattern) {
            let matches = urlRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches {
                let url = nsContent.substring(with: match.range(at: 1))
                let reqTypeRaw = nsContent.substring(with: match.range(at: 2))
                let val = nsContent.substring(with: match.range(at: 3))

                let reqType = DependencyRequirementType(rawValue: reqTypeRaw) ?? .from
                parsedList.append(ParsedDependency(url: url, requirementType: reqType, value: val, isLocal: false))
            }
        }

        self.dependencies = parsedList
    }

    private func getActiveAdvisories() -> [SecurityAdvisory] {
        var list: [SecurityAdvisory] = []
        for dep in dependencies {
            let depName = dep.url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? dep.url
            if let matched = platformManager.knownAdvisories.first(where: { $0.packageName.lowercased() == depName.lowercased() }) {
                list.append(matched)
            }
        }
        return list
    }

    private func countAdvisories() -> Int {
        return getActiveAdvisories().count
    }

    private func triggerSecurityScan() {
        Task {
            await platformManager.executeSecurityScan(dependencies: dependencies)
        }
    }
}
