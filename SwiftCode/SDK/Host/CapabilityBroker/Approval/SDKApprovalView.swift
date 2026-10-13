import Foundation
import SwiftUI

// MARK: - SDKApprovalRequest
//
// A capability approval request for one extension, handed to the host's
// approval UI before any privileged capability is activated (spec §8.3,
// ADR §5). The broker builds this from the validated manifest; the view
// performs no navigation and no persistence — the broker wires the
// onApprove/onDeny callbacks to the grant store and activation path.
//
// Implemented against the capability contract (SDKCapabilityID,
// SDKCapabilityRisk, SDKCapabilityInfo); the sibling subagent owns those
// types, so this file must not redefine them.

public struct SDKApprovalRequest: Sendable {
    public let extensionID: String
    public let extensionName: String
    public let extensionVersion: String
    /// SHA-256 package digest of the install being approved. Displayed
    /// truncated; the broker matches the full value before activating.
    public let packageDigest: String
    /// Only capabilities the extension actually requested. Spec §8.3
    /// forbids prompting for capabilities that were not requested.
    public let requestedCapabilities: [SDKCapabilityInfo]

    public init(
        extensionID: String,
        extensionName: String,
        extensionVersion: String,
        packageDigest: String,
        requestedCapabilities: [SDKCapabilityInfo]
    ) {
        self.extensionID = extensionID
        self.extensionName = extensionName
        self.extensionVersion = extensionVersion
        self.packageDigest = packageDigest
        self.requestedCapabilities = requestedCapabilities
    }
}

// MARK: - SDKApprovalView

/// Capability approval sheet for a SwiftCode extension.
///
/// Shows the extension identity and one row per requested capability with
/// plain-language effects. The user may approve a SUBSET: toggles default
/// ON only for low-risk capabilities and OFF for everything else; there is
/// no "allow everything" default. Restricted or otherwise ungrantable
/// capabilities cannot be toggled on and are labeled "Not available in
/// this release". The broker stores only the explicitly approved set
/// (spec §8.3.6) and returns a typed permission error on denial.
public struct SDKApprovalView: View {
    private let request: SDKApprovalRequest
    private let onApprove: (Set<SDKCapabilityID>) -> Void
    private let onDeny: () -> Void

    /// Currently selected (approved) capability IDs.
    @State private var selected: Set<SDKCapabilityID>

    public init(
        request: SDKApprovalRequest,
        onApprove: @escaping (Set<SDKCapabilityID>) -> Void,
        onDeny: @escaping () -> Void
    ) {
        self.request = request
        self.onApprove = onApprove
        self.onDeny = onDeny
        // Toggles default ON only for low-risk capabilities that are
        // grantable in this release. Medium/high are conservative-off;
        // restricted/grantableInCurrentRelease == false can never be on.
        _selected = State(initialValue: Set(
            request.requestedCapabilities
                .filter { $0.risk == .low && $0.grantableInCurrentRelease && $0.risk != .restricted }
                .map(\.id)
        ))
    }

    public var body: some View {
        VStack(spacing: 16) {
            headerView

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(request.requestedCapabilities, id: \.id) { info in
                        SDKCapabilityRow(
                            info: info,
                            isSelected: selected.contains(info.id),
                            onSelectionChange: { isOn in
                                if isOn {
                                    selected.insert(info.id)
                                } else {
                                    selected.remove(info.id)
                                }
                            }
                        )
                    }
                }
            }

            if request.requestedCapabilities.contains(where: { $0.id == .buildExecute }) {
                buildExecuteNote
            }

            onlyApprovedNote

            Divider()

            HStack(spacing: 12) {
                Button("Deny") {
                    onDeny()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Spacer()

                Button("Approve selected") {
                    onApprove(selected)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 480, maxWidth: 560)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 6) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)

            Text("Extension Requests Capabilities")
                .font(.title2)
                .bold()

            VStack(spacing: 2) {
                Text(request.extensionName)
                    .font(.headline)
                Text("\(request.extensionID) · v\(request.extensionVersion)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                Text("Package digest: \(Self.truncatedDigest(request.packageDigest))")
                    .font(.caption)
                    .monospaced()
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Honest notes

    /// Spec §8.3.4: state plainly that build.execute may run a
    /// potentially expensive build and that the host manages execution.
    private var buildExecuteNote: some View {
        Label {
            Text("Note: “Build” may run a potentially expensive build on your machine. Execution is managed by SwiftCode — the extension cannot run arbitrary build steps outside the approved scope.")
                .font(.callout)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var onlyApprovedNote: some View {
        Label {
            Text("Only the capabilities you leave on are granted. Anything you leave off stays denied until you explicitly change it.")
                .font(.callout)
                .foregroundColor(.secondary)
        } icon: {
            Image(systemName: "lock.fill")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func truncatedDigest(_ digest: String) -> String {
        guard digest.count > 16 else { return digest }
        return "\(digest.prefix(12))…"
    }
}

// MARK: - SDKCapabilityRow

/// One capability row: toggle, title, plain-language description,
/// grants/does-not-grant lines, and a risk badge.
///
/// The toggle is disabled for capabilities that are not grantable in this
/// release (restricted or `grantableInCurrentRelease == false`, e.g.
/// `assist.invoke` per ADR §9); such rows show "Not available in this
/// release" and can never contribute to the approved set.
public struct SDKCapabilityRow: View {
    private let info: SDKCapabilityInfo
    private let isSelected: Bool
    private let onSelectionChange: (Bool) -> Void

    public init(
        info: SDKCapabilityInfo,
        isSelected: Bool,
        onSelectionChange: @escaping (Bool) -> Void
    ) {
        self.info = info
        self.isSelected = isSelected
        self.onSelectionChange = onSelectionChange
    }

    private var isGrantable: Bool {
        info.grantableInCurrentRelease && info.risk != .restricted
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(info.title)
                            .font(.headline)
                        riskBadge
                    }
                    Text(info.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: Binding(
                    get: { isSelected && isGrantable },
                    set: { onSelectionChange($0) }
                ))
                .labelsHidden()
                .disabled(!isGrantable)
                .toggleStyle(.switch)
                .help(isGrantable
                      ? "Approve this capability"
                      : "Not available in this release")
            }

            grantsLines

            if !isGrantable {
                Label("Not available in this release", systemImage: "nosign")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected && isGrantable ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    private var grantsLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text(info.grantsSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text(info.doesNotGrant)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var riskBadge: some View {
        Text(info.risk.displayName)
            .font(.caption2)
            .bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(info.risk.badgeForeground)
            .background(info.risk.badgeBackground)
            .cornerRadius(4)
    }
}

// MARK: - Risk presentation helpers

extension SDKCapabilityRisk {
    var displayName: String {
        switch self {
        case .low: return "Low risk"
        case .medium: return "Medium risk"
        case .high: return "High risk"
        case .restricted: return "Restricted"
        }
    }

    var badgeForeground: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        case .restricted: return .secondary
        }
    }

    var badgeBackground: Color {
        switch self {
        case .low: return .green.opacity(0.12)
        case .medium: return .orange.opacity(0.12)
        case .high: return .red.opacity(0.12)
        case .restricted: return Color(NSColor.separatorColor).opacity(0.4)
        }
    }
}
