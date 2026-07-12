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
            ScrollView {
                VStack(spacing: 24) {

                    // Card 1: Add Apple Developer Account
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Add Apple Developer Account", systemImage: "person.crop.circle.badge.plus")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            Text("Connect your App Store Connect API Key to load and manage certificates, and codesign apps natively.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Apple ID (Email)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("e.g. developer@apple.com", text: $appleID)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Team Name")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("e.g. Acme Corp", text: $teamName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Team ID")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("e.g. 10-char alphanumeric", text: $teamID)
                                        .textFieldStyle(.roundedBorder)
                                        .autocorrectionDisabled()
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("API Key ID")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("e.g. ABC123XYZ", text: $keyID)
                                        .textFieldStyle(.roundedBorder)
                                        .autocorrectionDisabled()
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Issuer ID (UUID)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("e.g. e55f462a-...", text: $issuerID)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Private Key (.p8 Content)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                SecureField("Paste entire Private Key content here", text: $privateKey)
                                    .textFieldStyle(.roundedBorder)
                            }

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
                                        // Clear fields
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
                                    Text("Sign In / Connect API")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(.orange)
                            .disabled(appleID.isEmpty || teamID.isEmpty || keyID.isEmpty || issuerID.isEmpty || privateKey.isEmpty || manager.sessionState == .loading)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Security & Storage Info
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Security & Local Storage", systemImage: "lock.shield.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            Text("All private keys and API credentials are kept locally on your Mac inside the native secure Keychain Services. They are never sent to external servers other than Apple.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 3: Connected Accounts (Conditional)
                    if !manager.developerAccounts.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Connected Apple Accounts", systemImage: "person.crop.circle.badge.checkmark")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                    Spacer()
                                }

                                ForEach(manager.developerAccounts) { account in
                                    VStack(alignment: .leading, spacing: 8) {
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
                                            .padding(.top, 4)
                                        } else {
                                            Text("No active certificates found in this account.")
                                                .font(.caption.italic())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)

                                    if account.id != manager.developerAccounts.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // Card 4: Real App Codesign Utility
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Real App Codesign Utility", systemImage: "signature")
                                        .font(.headline)
                                        .foregroundColor(.purple)
                                    Spacer()
                                }

                                Text("Sign any macOS app bundle or binary file on this Mac using the certificates retrieved above.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("Note: The corresponding private key for the selected signing certificate must already be installed in your macOS Keychain for codesigning to succeed.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Target Application Path")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("e.g. /path/to/MyApp.app", text: $targetAppPath)
                                        .textFieldStyle(.roundedBorder)
                                        .autocorrectionDisabled()
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Signing Identity")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Picker("Identity", selection: $selectedCertificateName) {
                                        Text("Select an identity").tag("")
                                        ForEach(manager.developerAccounts) { account in
                                            if let certificates = account.certificates {
                                                ForEach(certificates) { cert in
                                                    Text("\(cert.name) (\(account.teamName))").tag(cert.name)
                                                }
                                            }
                                        }
                                    }
                                    .pickerStyle(.menu)
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
                                        Text("Codesign Application Bundle")
                                            .fontWeight(.bold)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(.purple)
                                .disabled(targetAppPath.isEmpty || selectedCertificateName.isEmpty || isCodesigning)

                                if !codesignStatusMessage.isEmpty {
                                    Text(codesignStatusMessage)
                                        .font(.caption.bold())
                                        .foregroundStyle(codesignStatusMessage.contains("Successfully") ? .green : .red)
                                        .padding(.top, 2)
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    // Card 5: Error Details (Conditional)
                    if let error = manager.lastError {
                        GroupBox {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Apple Developer Hub")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 550, idealWidth: 600, maxWidth: 800, minHeight: 500, idealHeight: 650, maxHeight: 900)
    }
}
