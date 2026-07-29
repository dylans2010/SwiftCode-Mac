import SwiftUI
import Appwrite
import os

private let logger = Logger(subsystem: "com.swiftcode.Auth", category: "CloudAuthViews")

@MainActor
struct CloudAuthViews: View {
    @Environment(\.dismiss) private var dismiss
    let onSuccess: () -> Void

    enum AuthMode {
        case login
        case createAccount
        case forgotPassword
    }

    @State private var mode: AuthMode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var authManager = AuthManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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

                        if mode == .createAccount {
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                    } header: {
                        Text("User Credentials")
                    }

                    if let error = errorMessage {
                        Section {
                            HStack {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption.bold())
                            }
                        }
                    }

                    if let success = successMessage {
                        Section {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(success)
                                    .foregroundColor(.green)
                                    .font(.caption.bold())
                            }
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

                    // Social Branded Identity Providers Section
                    if mode != .forgotPassword {
                        Section {
                            VStack(spacing: 12) {
                                BrandedGoogleButton {
                                    executeOAuthFlow(provider: "google")
                                }
                                .disabled(isLoading)

                                BrandedGitHubButton {
                                    executeOAuthFlow(provider: "github")
                                }
                                .disabled(isLoading)
                            }
                            .padding(.vertical, 4)
                        } header: {
                            Text("Or continue with")
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
        .frame(width: 440, height: mode == .forgotPassword ? 320 : 540)
    }

    private var navigationTitle: String {
        switch mode {
        case .login: return "Sign In to SwiftCode"
        case .createAccount: return "Create SwiftCode Account"
        case .forgotPassword: return "Reset Password Request"
        }
    }

    private var actionButtonTitle: String {
        switch mode {
        case .login: return "Sign In"
        case .createAccount: return "Register Account"
        case .forgotPassword: return "Send Password Reset Link"
        }
    }

    private var modeTextOption: String {
        switch mode {
        case .login: return "Don't have an account? Sign Up"
        case .createAccount: return "Already registered? Sign In"
        case .forgotPassword: return "Back to Sign In"
        }
    }

    private func switchMode() {
        errorMessage = nil
        successMessage = nil
        switch mode {
        case .login: mode = .createAccount
        case .createAccount: mode = .login
        case .forgotPassword: mode = .login
        }
    }

    private func executeAuthAction() {
        isLoading = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                if mode == .login {
                    try await authManager.login(email: email, password: SecureString(password))
                    logger.info("Successfully signed in via email & password.")
                    onSuccess()
                    dismiss()
                } else if mode == .createAccount {
                    guard password == confirmPassword else {
                        errorMessage = "Passwords do not match."
                        isLoading = false
                        return
                    }
                    try await authManager.createAccount(email: email, password: SecureString(password))
                    logger.info("Successfully registered and signed in new account.")
                    onSuccess()
                    dismiss()
                } else if mode == .forgotPassword {
                    try await authManager.forgotPassword(email: email)
                    successMessage = "A password reset link has been successfully dispatched to your email."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func executeOAuthFlow(provider: String) {
        isLoading = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                if provider == "google" {
                    try await authManager.loginWithGoogle()
                } else {
                    try await authManager.loginWithGitHub()
                }
                logger.info("OAuth session completed successfully for provider: \(provider)")
                onSuccess()
                dismiss()
            } catch {
                errorMessage = "OAuth Failed: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}

// MARK: - Google and GitHub Branded Buttons

struct BrandedGoogleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                HStack(spacing: 1) {
                    Text("G").bold().foregroundStyle(.blue)
                    Text("o").bold().foregroundStyle(.red)
                    Text("o").bold().foregroundStyle(.yellow)
                    Text("g").bold().foregroundStyle(.blue)
                    Text("l").bold().foregroundStyle(.green)
                    Text("e").bold().foregroundStyle(.red)
                }
                .font(.system(size: 14, weight: .heavy))

                Text("Continue with Google")
                    .foregroundColor(.black)
                    .font(.body.weight(.semibold))
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct BrandedGitHubButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.white)
                Text("Continue with GitHub")
                    .foregroundColor(.white)
                    .font(.body.weight(.semibold))
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
