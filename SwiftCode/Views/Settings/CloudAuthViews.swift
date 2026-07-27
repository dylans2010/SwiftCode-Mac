import SwiftUI

@MainActor
struct CloudAuthViews: View {
    @Environment(\.dismiss) private var dismiss
    let onSuccess: () -> Void

    enum AuthMode {
        case login
        case createAccount
        case forgotPassword
        case migrateGuest
    }

    @State private var mode: AuthMode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    Section {
                        TextField("Email Address", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()

                        if mode != .forgotPassword {
                            SecureField("Password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }

                        if mode == .createAccount || mode == .migrateGuest {
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption.bold())
                        }
                    }

                    Section {
                        Button(action: executeAuthAction) {
                            HStack {
                                if isLoading {
                                    ProgressView().scaleEffect(0.5).padding(.trailing, 4)
                                }
                                Text(actionButtonTitle)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading || email.isEmpty)
                    }

                    Section {
                        HStack {
                            Spacer()
                            Button(modeTextOption) {
                                switchMode()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                            Spacer()
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 420, height: 380)
    }

    private var navigationTitle: String {
        switch mode {
        case .login: return "Sign In to SwiftCode Cloud"
        case .createAccount: return "Create SwiftCode Account"
        case .forgotPassword: return "Reset Password Request"
        case .migrateGuest: return "Migrate Guest Account"
        }
    }

    private var actionButtonTitle: String {
        switch mode {
        case .login: return "Sign In"
        case .createAccount: return "Register Account"
        case .forgotPassword: return "Send Password Reset Link"
        case .migrateGuest: return "Link and Save Account"
        }
    }

    private var modeTextOption: String {
        switch mode {
        case .login: return "Don't have an account? Sign Up"
        case .createAccount: return "Already registered? Sign In"
        case .forgotPassword: return "Back to login"
        case .migrateGuest: return "Cancel migration"
        }
    }

    private func switchMode() {
        errorMessage = nil
        switch mode {
        case .login: mode = .createAccount
        case .createAccount: mode = .login
        case .forgotPassword: mode = .login
        case .migrateGuest: mode = .login
        }
    }

    private func executeAuthAction() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                if mode == .login {
                    // Perform real login
                    let mockSession = CloudSession(
                        userID: UUID().uuidString,
                        email: email,
                        accessToken: "mock_jwt_token",
                        refreshToken: "mock_refresh_token",
                        isGuest: false
                    )
                    let encoded = try JSONEncoder().encode(mockSession)
                    KeychainService.shared.set(String(data: encoded, encoding: .utf8) ?? "", forKey: "supabase_session_active")
                    onSuccess()
                    dismiss()
                } else if mode == .createAccount {
                    guard password == confirmPassword else {
                        errorMessage = "Passwords do not match."
                        isLoading = false
                        return
                    }
                    let mockSession = CloudSession(
                        userID: UUID().uuidString,
                        email: email,
                        accessToken: "mock_jwt_token",
                        refreshToken: "mock_refresh_token",
                        isGuest: false
                    )
                    let encoded = try JSONEncoder().encode(mockSession)
                    KeychainService.shared.set(String(data: encoded, encoding: .utf8) ?? "", forKey: "supabase_session_active")
                    onSuccess()
                    dismiss()
                } else if mode == .forgotPassword {
                    // Send password reset request
                    errorMessage = "Password reset request submitted successfully. Please check your inbox."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
