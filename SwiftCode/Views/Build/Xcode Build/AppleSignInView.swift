import SwiftUI

struct AppleSignInView: View {
    @State private var appleID = ""
    @State private var teamName = ""
    @State private var teamID = ""
    @State private var privateKey = ""
    @State private var mfaCode = ""

    @Environment(\.dismiss) private var dismiss

    private var manager: AppleSignInManager {
        AppleSignInManager.shared
    }

    var body: some View {
        NavigationStack {
            Form {
                if manager.sessionState == .requiresTwoFactor {
                    Section("Verification Code Sent") {
                        Text("A 6-digit verification code has been sent to your Apple devices. Please enter it below to complete sign-in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)

                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.orange)
                            TextField("6-Digit Code", text: $mfaCode)
                                .font(.system(.body, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .autocorrectionDisabled()
                        }
                    }

                    Section {
                        Button {
                            Task {
                                await manager.verifyTwoFactorCode(mfaCode)
                            }
                        } label: {
                            HStack {
                                if manager.sessionState == .loading {
                                    ProgressView().controlSize(.small)
                                        .padding(.trailing, 4)
                                }
                                Text("Verify & Connect")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(mfaCode.count != 6 || manager.sessionState == .loading)

                        Button("Cancel / Go Back") {
                            manager.sessionState = .signedOut
                            mfaCode = ""
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Section("Add Apple Developer Account") {
                        TextField("Apple ID (Email)", text: $appleID)
                            .autocorrectionDisabled()

                        TextField("Team Name", text: $teamName)

                        TextField("Team ID", text: $teamID)
                            .autocorrectionDisabled()

                        SecureField("App Store Connect API Key / Private Key", text: $privateKey)
                    }

                    Section {
                        Button {
                            Task {
                                await manager.sendTwoFactorCode(
                                    appleID: appleID,
                                    teamName: teamName,
                                    teamID: teamID,
                                    privateKey: privateKey
                                )
                                if manager.sessionState == .requiresTwoFactor {
                                    // Successfully went to 2FA phase, keep credentials
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
                        .disabled(appleID.isEmpty || teamID.isEmpty || privateKey.isEmpty || manager.sessionState == .loading)
                    }
                }

                Section("Privacy & Secure Storage") {
                    Label {
                        Text("All credentials and private keys are stored securely using macOS native Keychain Services. They are never logged or exposed externally.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !manager.developerAccounts.isEmpty {
                    Section("Connected Accounts") {
                        List {
                            ForEach(manager.developerAccounts) { account in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(account.teamName)
                                            .font(.body.bold())
                                        Text("\(account.appleID) (\(account.teamID))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .onDelete { indexSet in
                                manager.removeAccount(at: indexSet)
                            }
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
            .navigationTitle("Apple Developer Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 450)
    }
}
