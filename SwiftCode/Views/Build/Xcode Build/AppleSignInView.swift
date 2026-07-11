import SwiftUI

@MainActor
struct AppleSignInView: View {
    @State private var appleID = ""
    @State private var teamName = ""
    @State private var teamID = ""
    @State private var keyID = ""
    @State private var issuerID = ""
    @State private var privateKey = ""

    // Codesign tool fields
    @State private var targetAppPath = ""
    @State private var selectedCertificateName = ""
    @State private var codesignStatusMessage = ""
    @State private var isCodesigning = false

    @Environment(\.dismiss) private var dismiss

    private var manager: AppleSignInManager {
        AppleSignInManager.shared
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Add Apple Developer Account") {
                    Text("Connect your App Store Connect API Key to load and manage certificates, and codesign apps natively.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                    TextField("Apple ID (Email):", text: $appleID)
                        .autocorrectionDisabled()

                    TextField("Team Name:", text: $teamName)

                    TextField("Team ID:", text: $teamID)
                        .autocorrectionDisabled()

                    TextField("API Key ID:", text: $keyID)
                        .autocorrectionDisabled()

                    TextField("Issuer ID (UUID):", text: $issuerID)
                        .autocorrectionDisabled()

                    SecureField("Private Key:", text: $privateKey)
                }

                Section {
                    Button {
                        Task {
                            await manager.addAccount(
                                appleID: appleID,
                                teamName: teamName,
                                teamID: teamID,
                                keyID: keyID,
                                issuerID: issuerID,
                                privateKey: privateKey
                            )
                            if manager.sessionState == .signedIn {
                                // Clear input fields on successful connection
                                appleID = ""
                                teamName = ""
                                teamID = ""
                                keyID = ""
                                issuerID = ""
                                privateKey = ""
                            }
                        }
                    } label: {
                        HStack {
                            if manager.sessionState == .loading {
                                ProgressView().controlSize(.small)
                                    .padding(.trailing, 4)
                            }
                            Text("Sign In / Connect")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appleID.isEmpty || teamID.isEmpty || keyID.isEmpty || issuerID.isEmpty || privateKey.isEmpty || manager.sessionState == .loading)
                }

                Section("Security & Storage") {
                    Label {
                        Text("All private keys and API credentials are kept locally on your Mac inside the native secure Keychain Services. They are never sent to external servers other than Apple.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !manager.developerAccounts.isEmpty {
                    Section("Connected Accounts") {
                        ForEach(manager.developerAccounts) { account in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.teamName)
                                            .font(.body.bold())
                                        Text("\(account.appleID) (Team ID: \(account.teamID))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()

                                    Button(role: .destructive) {
                                        if let index = manager.developerAccounts.firstIndex(where: { $0.id == account.id }) {
                                            manager.removeAccount(at: IndexSet(integer: index))
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove Account")
                                    .padding(.trailing, 8)

                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }

                                if let certificates = account.certificates, !certificates.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Active Signing Certificates:")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 4)

                                        ForEach(certificates) { cert in
                                            HStack {
                                                Image(systemName: "key.fill")
                                                    .foregroundStyle(.orange)
                                                    .imageScale(.small)
                                                Text("\(cert.name) (\(cert.type))")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                } else {
                                    Text("No active certificates found in this account.")
                                        .font(.caption.italic())
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Section("Real App Codesign Utility") {
                        Text("Sign any macOS app bundle or binary file on this Mac using the certificates retrieved above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Note: The corresponding private key for the selected signing certificate must already be installed in your macOS Keychain for codesigning to succeed.")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        TextField("App Bundle or Binary Path (e.g. /path/to/MyApp.app)", text: $targetAppPath)
                            .autocorrectionDisabled()

                        Picker("Select Signing Identity", selection: $selectedCertificateName) {
                            Text("Select an identity").tag("")
                            ForEach(manager.developerAccounts) { account in
                                if let certificates = account.certificates {
                                    ForEach(certificates) { cert in
                                        Text("\(cert.name) (\(account.teamName))").tag(cert.name)
                                    }
                                }
                            }
                        }

                        Button {
                            Task {
                                isCodesigning = true
                                codesignStatusMessage = "Signing..."
                                do {
                                    let success = try await manager.codesign(
                                        appPath: targetAppPath,
                                        withCertificateName: selectedCertificateName
                                    )
                                    if success {
                                        codesignStatusMessage = "Successfully codesigned!"
                                    } else {
                                        codesignStatusMessage = "Codesign failed."
                                    }
                                } catch {
                                    codesignStatusMessage = "Error: \(error.localizedDescription)"
                                }
                                isCodesigning = false
                            }
                        } label: {
                            HStack {
                                if isCodesigning {
                                    ProgressView().controlSize(.small)
                                        .padding(.trailing, 4)
                                }
                                Text("Codesign App")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(targetAppPath.isEmpty || selectedCertificateName.isEmpty || isCodesigning)

                        if !codesignStatusMessage.isEmpty {
                            Text(codesignStatusMessage)
                                .font(.caption.bold())
                                .foregroundStyle(codesignStatusMessage.contains("Successfully") ? .green : .red)
                                .padding(.top, 2)
                        }
                    }
                }

                if let error = manager.lastError {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Apple Developer Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 550, maxWidth: 800, minHeight: 500, idealHeight: 650, maxHeight: 900)
    }
}
