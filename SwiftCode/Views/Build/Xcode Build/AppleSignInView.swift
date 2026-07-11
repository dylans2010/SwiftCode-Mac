import SwiftUI

struct AppleSignInView: View {
    @State private var appleID = ""
    @State private var teamName = ""
    @State private var teamID = ""
    @State private var privateKey = ""

    @Environment(\.dismiss) private var dismiss

    private var manager: AppleSignInManager {
        AppleSignInManager.shared
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Add Apple Developer Account") {
                    TextField("Apple ID (Email)", text: $appleID)
                        .autocorrectionDisabled()

                    TextField("Team Name", text: $teamName)

                    TextField("Team ID", text: $teamID)
                        .autocorrectionDisabled()

                    SecureField("App Store Connect API Key / Private Key", text: $privateKey)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign In / Connect") {
                        Task {
                            await manager.addAccount(
                                appleID: appleID,
                                teamName: teamName,
                                teamID: teamID,
                                privateKey: privateKey
                            )
                            if manager.lastError == nil {
                                appleID = ""
                                teamName = ""
                                teamID = ""
                                privateKey = ""
                            }
                        }
                    }
                    .disabled(appleID.isEmpty || teamID.isEmpty || privateKey.isEmpty)
                }
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
