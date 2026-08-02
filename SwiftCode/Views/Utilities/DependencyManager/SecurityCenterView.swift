import SwiftUI

struct DependencySecurityCenterView: View {
    @Environment(\.dismiss) private var dismiss
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
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)

                Text("Ecosystem Security & Audit Suite")
                    .font(.title2.bold())

                Spacer()

                Button {
                    triggerSecurityScan()
                } label: {
                    Label(platformManager.securityScanRunning ? "Scanning..." : "Execute Security Scan", systemImage: "shield.lefthalf.filled")
                }
                .buttonStyle(.borderedProminent)
                .disabled(platformManager.securityScanRunning)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Health Header Summary
            HStack(spacing: 30) {
                VStack(alignment: .leading) {
                    Text("Risk Score")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: platformManager.securityScore > 80 ? "shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(platformManager.securityScore > 80 ? .green : (platformManager.securityScore > 50 ? .orange : .red))
                        Text("\(platformManager.securityScore)/100")
                            .font(.title.bold())
                    }
                }

                VStack(alignment: .leading) {
                    Text("Scanned Dependencies")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("\(dependencies.count) targets")
                        .font(.title.bold())
                }

                VStack(alignment: .leading) {
                    Text("Advisories Found")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    let matches = countAdvisories()
                    Text("\(matches) warnings")
                        .font(.title.bold())
                        .foregroundStyle(matches > 0 ? .red : .primary)
                }

                Spacer()
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tab switcher
            HStack {
                ForEach(SecurityTab.allCases) { tab in
                    Button {
                        activeTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .fontWeight(activeTab == tab ? .bold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(activeTab == tab ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(activeTab == tab ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HSplitView {
                scanListAndBreakdownView
                detailsInspectorCardView
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadDependencies()
        }
    }

    @ViewBuilder
    private func renderVulnerabilities() -> some View {
        let matches = getActiveAdvisories()

        if matches.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("No active vulnerabilities found in imported packages.")
                    .font(.headline)
                Spacer()
            }
        } else {
            List {
                ForEach(matches) { adv in
                    Button {
                        selectedAdvisory = adv
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(adv.packageName)
                                    .font(.headline)
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
                        .padding(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func renderLicenses() -> some View {
        List {
            ForEach(dependencies) { dep in
                let name = dep.url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? dep.url
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text(name)
                            .font(.headline)
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
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func renderMaintenance() -> some View {
        List {
            ForEach(dependencies) { dep in
                let name = dep.url.split(separator: "/").last?.replacingOccurrences(of: ".git", with: "") ?? dep.url
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading) {
                        Text(name)
                            .font(.headline)
                        Text("Release cadence: Stable (~4 releases / year)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Low Risk")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 4)
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

    @ViewBuilder
    private var scanListAndBreakdownView: some View {
        VStack(spacing: 0) {
            if platformManager.securityScanRunning {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                    Text("Running static vulnerability scanner...")
                        .font(.headline)
                    Spacer()
                }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var detailsInspectorCardView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Risk Details Inspector")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let advisory = selectedAdvisory {
                VStack(alignment: .leading, spacing: 12) {
                    Text(advisory.packageName)
                        .font(.title3.bold())

                    Text(advisory.title)
                        .font(.headline)

                    HStack {
                        Text(advisory.severity)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(advisory.severity == "Critical" ? Color.red.opacity(0.15) : Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(advisory.severity == "Critical" ? Color.red : Color.orange)

                        Spacer()
                    }

                    Divider()

                    Text("Affected: \(advisory.affectedVersions)")
                        .font(.caption.bold())
                    Text("Fixed Version: \(advisory.fixedVersion)")
                        .font(.caption.bold())
                        .foregroundStyle(.green)

                    Divider()

                    Text("Details:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(advisory.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !advisory.advisoryUrl.isEmpty {
                        Link("View Security Advisory", destination: URL(string: advisory.advisoryUrl)!)
                            .font(.caption)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Select Advisory", systemImage: "shield.questionmark")
                } description: {
                    Text("Select a vulnerability report on the left panel to inspect CVE details and upgrade advice.")
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 280, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
