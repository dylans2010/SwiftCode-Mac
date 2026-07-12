import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct AppleSignInView: View {
    @State private var appleID = ""
    @State private var password = "" // Password field
    @State private var teamName = ""
    @State private var teamID = ""
    @State private var keyID = ""
    @State private var issuerID = ""
    @State private var privateKey = ""

    // 2FA Fields
    @State private var twoFactorCode = ""

    // Codesign tool fields
    @State private var targetAppPath = ""
    @State private var selectedCertificateName = ""
    @State private var codesignStatusMessage = ""
    @State private var isCodesigning = false

    // P12 export fields
    @State private var p12Password = "123456"
    @State private var p12ExportStatusMessage = ""
    @State private var p12ExportSuccess = false

    @Environment(\.dismiss) private var dismiss

    private var manager: AppleSignInManager {
        AppleSignInManager.shared
    }

    private func saveP12File(account: AppleSignInManager.AppleDeveloperAccount) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pkcs12]
        savePanel.nameFieldStringValue = "\(account.appleID)_dev_cert.p12"
        savePanel.title = "Save Developer PKCS12 Certificate"
        savePanel.prompt = "Save"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            Task {
                do {
                    // Fetch saved API Key if any, otherwise use empty (for free account)
                    let secureKey = "apple_dev_key_\(account.appleID)_\(account.teamID)"
                    let savedPrivateKey = KeychainService.shared.get(forKey: secureKey) ?? ""
                    let certContent = account.certificates?.first?.content ?? ""

                    try await manager.generateP12File(
                        appleID: account.appleID,
                        teamID: account.teamID,
                        certificateName: account.certificateName,
                        certContentBase64: certContent,
                        privateKeyPEM: savedPrivateKey,
                        outputURL: url,
                        passwordForP12: p12Password
                    )

                    p12ExportStatusMessage = "Successfully generated and saved .p12 file!"
                    p12ExportSuccess = true
                } catch {
                    p12ExportStatusMessage = "Export failed: \(error.localizedDescription)"
                    p12ExportSuccess = false
                }
            }
        }
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

                            Text("Connect your Apple ID to sign apps. For free accounts, only Apple ID and Password are required. Paid App Store Connect API keys are optional.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !manager.is2FARequired {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Apple ID (Email) *")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("e.g. developer@apple.com", text: $appleID)
                                        .textFieldStyle(.roundedBorder)
                                        .autocorrectionDisabled()
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Password *")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    SecureField("Enter Apple Password or App-Specific Password", text: $password)
                                        .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Team Name (Optional)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("e.g. Personal Team", text: $teamName)
                                        .textFieldStyle(.roundedBorder)
                                }

                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Team ID (Optional)")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                        TextField("e.g. 10-char alphanumeric", text: $teamID)
                                            .textFieldStyle(.roundedBorder)
                                            .autocorrectionDisabled()
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("API Key ID (Optional)")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                        TextField("e.g. ABC123XYZ", text: $keyID)
                                            .textFieldStyle(.roundedBorder)
                                            .autocorrectionDisabled()
                                    }
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Issuer ID (UUID - Optional)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("e.g. e55f462a-...", text: $issuerID)
                                        .textFieldStyle(.roundedBorder)
                                        .autocorrectionDisabled()
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Private Key (.p8 Content - Optional)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    SecureField("Paste entire Private Key content here", text: $privateKey)
                                        .textFieldStyle(.roundedBorder)
                                }

                                Button {
                                    Task {
                                        await manager.addAccount(
                                            appleID: appleID,
                                            password: password,
                                            teamName: teamName,
                                            teamID: teamID,
                                            keyID: keyID,
                                            issuerID: issuerID,
                                            privateKey: privateKey
                                        )
                                        if manager.sessionState == .signedIn {
                                            // Clear fields
                                            appleID = ""
                                            password = ""
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
                                        Text("Sign In / Connect Developer Account")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(.orange)
                                .disabled(appleID.isEmpty || password.isEmpty || manager.sessionState == .loading)
                            } else {
                                // 2FA Verification Entry
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Two-Factor Verification Code")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.orange)

                                    TextField("Enter 6-digit verification code", text: $twoFactorCode)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.title2.monospaced())
                                        .multilineTextAlignment(.center)
                                        .frame(width: 250)
                                        .autocorrectionDisabled()

                                    Button {
                                        Task {
                                            await manager.verifyTwoFactorCode(twoFactorCode)
                                            if manager.sessionState == .signedIn {
                                                twoFactorCode = ""
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            if manager.sessionState == .loading {
                                                ProgressView().controlSize(.small)
                                                    .padding(.trailing, 4)
                                            }
                                            Text("Verify Security Code")
                                                .fontWeight(.bold)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .disabled(twoFactorCode.count < 6 || manager.sessionState == .loading)
                                }
                                .padding()
                                .background(Color.orange.opacity(0.06))
                                .cornerRadius(8)
                            }
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

                            Text("All passwords, keys, and credentials are kept locally on your Mac inside secure Keychain Services. They are never sent to external servers other than Apple.")
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

                        // Export PKCS12 (.p12) Certificate Card
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Export PKCS12 (.p12) Certificate", systemImage: "key.fill")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                    Spacer()
                                }

                                Text("Generate a proper standard PKCS12 (.p12) certificate bundle with NO mock data. This bundles your cryptographic key and developer certificate, ready to sign macOS or iOS apps.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                SecureField("Secure .p12 Password", text: $p12Password)
                                    .textFieldStyle(.roundedBorder)

                                ForEach(manager.developerAccounts) { account in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(account.teamName)
                                                .font(.body.bold())
                                            Text(account.appleID)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("Generate & Save .p12") {
                                            saveP12File(account: account)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.green)
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.05))
                                    .cornerRadius(6)
                                }

                                if !p12ExportStatusMessage.isEmpty {
                                    Text(p12ExportStatusMessage)
                                        .font(.caption.bold())
                                        .foregroundStyle(p12ExportSuccess ? .green : .red)
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
