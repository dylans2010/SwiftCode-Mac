import Foundation
import SwiftUI

// MARK: - AssistAccessFormView
//
// Studio → Assist Access: the developer-facing Assist authorization flow
// (Docs/Intro-to-SDK.md §10 — Part B).
//
// Two parts in one view:
//   1. The application form — all required fields of the Assist access
//      application, validated field-by-field by
//      `SDKAssistApplication.validate()` (inline per-field error text) and
//      by `SDKAssistApplicationStore.submit` (extension-identity registry
//      check + API-key existence check, also surfaced per field).
//   2. The pending-applications queue — every pending application with
//      Approve / Deny wired to `SDKAssistApplicationStore.approve` / `.deny`.
//      Approving IS the entitlement grant path: the store grants
//      `com.SwiftCode.developer-AI-Assist` (plus
//      `com.SwiftCode.developer-AI-Allows-Cloud` when the application
//      declares third-party models or off-device data) on the applicant's
//      API key before the record is marked approved.
//
// Approval policy (v1): recorded self-attestation with revocation-on-abuse —
// no human review queue; approval records the developer's answers as their
// attestation, and abuse after approval is handled by entitlement
// revocation (immediate at the authorization boundary, audit-logged).
//
// Native SwiftUI + Foundation only: no AppKit import.

public struct AssistAccessFormView: View {
    public init() {}

    // MARK: - Form state

    @State private var extensionID = ""
    @State private var displayName = ""
    @State private var selectedKeyID: UUID?
    @State private var keys: [SDKAPIKey] = []
    @State private var variant: SDKAssistSDKVariant = .assistSDKUI
    @State private var usageDescription = ""
    @State private var hasOwnUI: Bool?
    @State private var ownUIDescription = ""
    @State private var usesThirdPartyModels: Bool?
    @State private var thirdPartyModels = ""
    @State private var dataLeavesDevice: Bool?
    @State private var dataDestination = ""
    @State private var contactEmail = ""

    // MARK: - View state

    @State private var fieldErrors: [SDKAssistApplicationField: String] = [:]
    @State private var isSubmitting = false
    @State private var notice: Notice?
    @State private var pendingApplications: [SDKAssistApplication] = []
    @State private var decidedApplications: [SDKAssistApplication] = []
    @State private var isLoadingQueue = false
    @State private var denyingTarget: SDKAssistApplication?
    @State private var confirmingDeny = false
    @State private var actionInFlight: UUID?

    private struct Notice: Identifiable {
        let id = UUID()
        let isError: Bool
        let text: String
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introText
                    formSection
                    queueSection
                }
                .padding()
            }
            .navigationTitle("Assist Access")
            .task {
                await reload()
            }
        }
    }

    // MARK: - Intro

    private var introText: some View {
        Text("Third-party apps may use Assist only after an approved Assist access application. Applications are recorded self-attestations: approval grants key-bound entitlements on the applicant's developer API key (never the manifest), and abuse after approval is handled by entitlement revocation, which takes effect immediately at the authorization boundary.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    // MARK: - Application form

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Application")
                .font(.title2)
                .bold()

            appIdentityFields
            apiKeyPicker
            variantPicker
            usageField
            yesNoField(
                title: "Do you have your own UI for Assist responses?",
                subtitle: "Required — this choice determines which SDK variant fits your app.",
                selection: $hasOwnUI,
                field: .hasOwnUI,
                followUpTitle: "Describe your UI for Assist responses",
                followUpText: $ownUIDescription,
                followUpField: .ownUIDescription,
                showFollowUp: hasOwnUI == true
            )
            yesNoField(
                title: "Will third-party models outside SwiftCode be used?",
                subtitle: "Required.",
                selection: $usesThirdPartyModels,
                field: .usesThirdPartyModels,
                followUpTitle: "List the third-party providers and models",
                followUpText: $thirdPartyModels,
                followUpField: .thirdPartyModels,
                showFollowUp: usesThirdPartyModels == true
            )
            yesNoField(
                title: "Does user data leave the device?",
                subtitle: "Required.",
                selection: $dataLeavesDevice,
                field: .dataLeavesDevice,
                followUpTitle: "Where does user data go?",
                followUpText: $dataDestination,
                followUpField: .dataDestination,
                showFollowUp: dataLeavesDevice == true
            )
            contactField

            HStack {
                Spacer()
                Button("Submit Application") {
                    Task { @MainActor in await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting)
            }

            if let notice {
                noticeBanner(notice)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Form field groups

    private var appIdentityFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App identity")
                .font(.headline)
            LabeledTextField(
                label: "Extension ID",
                placeholder: "e.g. com.example.myapp",
                text: $extensionID,
                error: fieldErrors[.extensionID]
            )
            Text("Must match an installed/registered app — checked against the extension registry on submit.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledTextField(
                label: "Display name",
                placeholder: "e.g. My App",
                text: $displayName,
                error: fieldErrors[.displayName]
            )
        }
    }

    private var apiKeyPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Developer API key")
                .font(.headline)
            if keys.isEmpty {
                Text("No developer API keys exist yet. Generate one in Studio → Settings → Developer API Keys — entitlements are bound to the key on approval.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Developer API key", selection: $selectedKeyID) {
                    Text("Select a key…").tag(nil as UUID?)
                    ForEach(keys, id: \.id) { key in
                        Text("\(key.label) (\(key.keyPrefix)…)").tag(key.id as UUID?)
                    }
                }
                .labelsHidden()
            }
            inlineError(fieldErrors[.apiKey])
        }
    }

    private var variantPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SDK variant")
                .font(.headline)
            Picker("SDK variant", selection: $variant) {
                ForEach(SDKAssistSDKVariant.allCases, id: \.self) { option in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.displayLabel)
                        Text(option.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(option)
                }
            }
            .pickerStyle(.radioGroup)
            inlineError(fieldErrors[.sdkVariant])
        }
    }

    private var usageField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How will Assist be used in your app?")
                .font(.headline)
            TextEditor(text: $usageDescription)
                .frame(minHeight: 110)
                .border(.quaternary, width: 1)
                .font(.body)
            HStack {
                Text("\(usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).count)/\(SDKAssistApplication.minimumUsageDescriptionLength) characters minimum")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("Stored verbatim with the application as your self-attestation.")
                .font(.caption)
                .foregroundStyle(.secondary)
            inlineError(fieldErrors[.usageDescription])
        }
    }

    /// A required Yes/No choice with an optional conditional follow-up text
    /// field. `selection` stays nil until the user explicitly picks one, so
    /// an unanswered question is a validation error, never a silent default.
    private func yesNoField(
        title: String,
        subtitle: String,
        selection: Binding<Bool?>,
        field: SDKAssistApplicationField,
        followUpTitle: String,
        followUpText: Binding<String>,
        followUpField: SDKAssistApplicationField,
        showFollowUp: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                yesNoOption(label: "Yes", value: true, selection: selection)
                yesNoOption(label: "No", value: false, selection: selection)
            }
            inlineError(fieldErrors[field])
            if showFollowUp {
                LabeledTextField(
                    label: followUpTitle,
                    placeholder: "",
                    text: followUpText,
                    error: fieldErrors[followUpField]
                )
            }
        }
    }

    private func yesNoOption(label: String, value: Bool, selection: Binding<Bool?>) -> some View {
        Button {
            selection.wrappedValue = value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection.wrappedValue == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selection.wrappedValue == value ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
                Text(label)
            }
        }
        .buttonStyle(.plain)
    }

    private var contactField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Contact email")
                .font(.headline)
            TextField("you@example.com", text: $contactEmail)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
            inlineError(fieldErrors[.contactEmail])
        }
    }

    // MARK: - Submit

    @MainActor
    private func submit() async {
        fieldErrors = [:]
        notice = nil

        // The record requires explicit Yes/No answers; an unanswered
        // question is a field error, not a silent default.
        if hasOwnUI == nil {
            fieldErrors[.hasOwnUI] = "Choose Yes or No."
        }
        if usesThirdPartyModels == nil {
            fieldErrors[.usesThirdPartyModels] = "Choose Yes or No."
        }
        if dataLeavesDevice == nil {
            fieldErrors[.dataLeavesDevice] = "Choose Yes or No."
        }
        guard let selectedKeyID else {
            fieldErrors[.apiKey] = "Select the developer API key the entitlements will be bound to."
            return
        }
        guard
            let hasOwnUI,
            let usesThirdPartyModels,
            let dataLeavesDevice
        else { return }

        let draft = SDKAssistApplication(
            extensionID: extensionID,
            displayName: displayName,
            apiKeyID: selectedKeyID,
            sdkVariant: variant,
            usageDescription: usageDescription,
            hasOwnUI: hasOwnUI,
            ownUIDescription: ownUIDescription,
            usesThirdPartyModels: usesThirdPartyModels,
            thirdPartyModels: thirdPartyModels,
            dataLeavesDevice: dataLeavesDevice,
            dataDestination: dataDestination,
            contactEmail: contactEmail
        )

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let stored = try await SDKAssistApplicationStore.shared.submit(draft)
            resetForm()
            await reload()
            notice = Notice(
                isError: false,
                text: "Application submitted for “\(stored.displayName)” — it is pending review in the queue below."
            )
        } catch let validationError as SDKAssistApplicationValidationError {
            fieldErrors = validationError.errors
        } catch {
            notice = Notice(isError: true, text: presentableError(error))
        }
    }

    @MainActor
    private func resetForm() {
        extensionID = ""
        displayName = ""
        selectedKeyID = nil
        variant = .assistSDKUI
        usageDescription = ""
        hasOwnUI = nil
        ownUIDescription = ""
        usesThirdPartyModels = nil
        thirdPartyModels = ""
        dataLeavesDevice = nil
        dataDestination = ""
        contactEmail = ""
        fieldErrors = [:]
    }

    // MARK: - Review queue

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Pending Applications")
                    .font(.title2)
                    .bold()
                Spacer()
                if isLoadingQueue {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { @MainActor in await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }
            }

            if pendingApplications.isEmpty && !isLoadingQueue {
                Text("No pending applications.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pendingApplications, id: \.id) { application in
                    pendingRow(application)
                }
            }

            if !decidedApplications.isEmpty {
                Text("Decided")
                    .font(.headline)
                    .padding(.top, 8)
                ForEach(decidedApplications, id: \.id) { application in
                    decidedRow(application)
                }
            }
        }
    }

    private func pendingRow(_ application: SDKAssistApplication) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(application.displayName)
                        .font(.headline)
                    Text(application.extensionID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusChip(application.status)
            }
            HStack(spacing: 8) {
                Text(application.sdkVariant.displayLabel)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Text("Contact: \(application.contactEmail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if application.hasOwnUI {
                Text("Own UI: \(application.ownUIDescription ?? "—")")
                    .font(.callout)
            } else {
                Text("Own UI: none — embeds SwiftCode's Assist interface.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("“\(application.usageDescription)”")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if application.usesThirdPartyModels {
                Text("Third-party models: \(application.thirdPartyModels ?? "—")")
                    .font(.callout)
            }
            if application.dataLeavesDevice {
                Text("Data leaves device → \(application.dataDestination ?? "—")")
                    .font(.callout)
            }
            Text("Submitted \(application.submittedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                if actionInFlight == application.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Deny") {
                        denyingTarget = application
                        confirmingDeny = true
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(.red)
                    Button("Approve") {
                        Task { @MainActor in await approve(application) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
        .alert("Deny this application?", isPresented: $confirmingDeny, presenting: denyingTarget) { target in
            Button("Cancel", role: .cancel) {}
            Button("Deny Application", role: .destructive) {
                Task { @MainActor in await deny(target) }
            }
        } message: { target in
            Text("“\(target.displayName)” will be marked denied. No entitlements are granted. This cannot be undone.")
        }
    }

    private func decidedRow(_ application: SDKAssistApplication) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(application.displayName)
                    .font(.body)
                Text("\(application.extensionID) · \(application.sdkVariant.displayLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusChip(application.status)
            if let decidedAt = application.decidedAt {
                Text(decidedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(application.status == .denied ? 0.6 : 1.0)
    }

    private func statusChip(_ status: SDKAssistApplicationStatus) -> some View {
        let (text, color): (String, Color) = switch status {
        case .pending: ("Pending", .orange)
        case .approved: ("Approved", .green)
        case .denied: ("Denied", .red)
        }
        return Text(text)
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Decide actions

    @MainActor
    private func approve(_ application: SDKAssistApplication) async {
        notice = nil
        actionInFlight = application.id
        defer { actionInFlight = nil }
        do {
            let decided = try await SDKAssistApplicationStore.shared.approve(id: application.id)
            await reload()
            let keyLabel = keys.first(where: { $0.id == decided.apiKeyID })?.label ?? "the applicant's API key"
            notice = Notice(
                isError: false,
                text: "Approved “\(decided.displayName)” — the Assist entitlement was granted on “\(keyLabel)”."
                    + (decided.usesThirdPartyModels || decided.dataLeavesDevice ? " The cloud-model entitlement was also granted." : "")
            )
        } catch {
            notice = Notice(isError: true, text: presentableError(error))
        }
    }

    @MainActor
    private func deny(_ application: SDKAssistApplication) async {
        notice = nil
        denyingTarget = nil
        actionInFlight = application.id
        defer { actionInFlight = nil }
        do {
            let decided = try await SDKAssistApplicationStore.shared.deny(id: application.id)
            await reload()
            notice = Notice(isError: false, text: "Denied “\(decided.displayName)” — no entitlements were granted.")
        } catch {
            notice = Notice(isError: true, text: presentableError(error))
        }
    }

    // MARK: - Loading

    @MainActor
    private func reload() async {
        isLoadingQueue = true
        defer { isLoadingQueue = false }
        keys = await SDKAPIKeyStore.shared.list()
        let all = await SDKAssistApplicationStore.shared.list()
        pendingApplications = all.filter { $0.status == .pending }
        decidedApplications = all.filter { $0.status != .pending }
        if let selectedKeyID, !keys.contains(where: { $0.id == selectedKeyID }) {
            self.selectedKeyID = nil
        }
    }

    // MARK: - Shared UI helpers

    @ViewBuilder
    private func inlineError(_ text: String?) -> some View {
        if let text {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func noticeBanner(_ notice: Notice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? .red : .green)
            Text(notice.text)
                .font(.callout)
            Spacer()
            Button {
                self.notice = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(10)
        .background((notice.isError ? Color.red : Color.green).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    @MainActor
    private func presentableError(_ error: Error) -> String {
        if let sdkError = error as? SDKError {
            return [sdkError.message, sdkError.suggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        return error.localizedDescription
    }
}

// MARK: - LabeledTextField

/// A labeled text field with inline error text, shared by the Assist access
/// form's one-line fields.
private struct LabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.headline)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
            if let error {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
