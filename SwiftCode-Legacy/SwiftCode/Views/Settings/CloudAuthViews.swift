import SwiftUI
import Appwrite
import os

private let logger = Logger(subsystem: "com.swiftcode.Auth", category: "CloudAuthViews")

@MainActor
struct CloudAuthViews: View {
    @Environment(\.dismiss) private var dismiss
    var isGate: Bool = false
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
            ScrollView {
                VStack(spacing: 24) {
                    /// Header Branding Card
                    GroupBox {
                        VStack(spacing: 8) {
                            Image(systemName: "icloud.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.blue)
                                .padding(.top, 8)

                            Text(headerTitle)
                                .font(.title2.bold())

                            Text(headerSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    /// Credentials Entry Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Account Details")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Email Address")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("name@example.com", text: $email)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.emailAddress)
                                    .autocorrectionDisabled()
                                    .disabled(isLoading || authManager.isLoading)
                            }

                            if mode != .forgotPassword {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Password")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    SecureField("Enter secure password", text: $password)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isLoading || authManager.isLoading)
                                }
                            }

                            if mode == .createAccount {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Confirm Password")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    SecureField("Re-enter secure password", text: $confirmPassword)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isLoading || authManager.isLoading)
                                }
                            }

                            if let error = errorMessage ?? authManager.authError {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.octagon.fill")
                                        .foregroundColor(.red)
                                    Text(error)
                                        .foregroundColor(.red)
                                        .font(.caption.bold())
                                        .lineLimit(3)
                                }
                                .padding(.top, 4)
                            }

                            if let success = successMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(success)
                                        .foregroundColor(.green)
                                        .font(.caption.bold())
                                        .lineLimit(3)
                                }
                                .padding(.top, 4)
                            }

                            Button(action: executeAuthAction) {
                                HStack {
                                    if isLoading || authManager.isLoading {
                                        ProgressView().scaleEffect(0.5).padding(.trailing, 4)
                                    }
                                    Text(actionButtonTitle)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isLoading || authManager.isLoading || email.isEmpty || (mode != .forgotPassword && password.isEmpty))
                        }
                        .padding(6)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    /// Social Providers Card
                    if mode != .forgotPassword {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Or continue with")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)

                                VStack(spacing: 12) {
                                    BrandedGoogleButton {
                                        executeOAuthFlow(provider: "google")
                                    }
                                    .disabled(isLoading || authManager.isLoading)

                                    BrandedGitHubButton {
                                        executeOAuthFlow(provider: "github")
                                    }
                                    .disabled(isLoading || authManager.isLoading)
                                }
                            }
                            .padding(6)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }

                    /// Toggle View mode button
                    Button {
                        withAnimation {
                            switchMode()
                        }
                    } label: {
                        Text(modeTextOption)
                            .font(.subheadline.bold())
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || authManager.isLoading)
                    .padding(.vertical, 8)
                }
                .padding(24)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .navigationTitle(navigationTitle)
            .toolbar {
                if !isGate {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .frame(width: 460, height: mode == .forgotPassword ? 480 : 680)
    }

    private var navigationTitle: String {
        switch mode {
        case .login: return "Sign In"
        case .createAccount: return "Register"
        case .forgotPassword: return "Reset Password"
        }
    }

    private var headerTitle: String {
        switch mode {
        case .login: return "Welcome to SwiftCode"
        case .createAccount: return "Create Cloud Account"
        case .forgotPassword: return "Recover Account"
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .login: return "Access secure cloud synchronization and automatic backups for all your developer tools."
        case .createAccount: return "Unlock real-time synchronization, template sharing, and on-device offline models metadata syncing."
        case .forgotPassword: return "Enter your registered email address and we will dispatch a secure link to reset your account password."
        }
    }

    private var actionButtonTitle: String {
        switch mode {
        case .login: return "Sign In with Password"
        case .createAccount: return "Register Secure Account"
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
                    if !isGate {
                        dismiss()
                    }
                } else if mode == .createAccount {
                    guard password == confirmPassword else {
                        errorMessage = "Passwords do not match."
                        isLoading = false
                        return
                    }
                    try await authManager.createAccount(email: email, password: SecureString(password))
                    logger.info("Successfully registered and signed in new account.")
                    onSuccess()
                    if !isGate {
                        dismiss()
                    }
                } else if mode == .forgotPassword {
                    try await authManager.forgotPassword(email: email)
                    successMessage = "A password reset link has been successfully dispatched to your email."
                }
            } catch {
                errorMessage = mapErrorToUserMessage(error)
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
                if !isGate {
                    dismiss()
                }
            } catch {
                errorMessage = "OAuth Failed: \(mapErrorToUserMessage(error))"
            }
            isLoading = false
        }
    }

    private func mapErrorToUserMessage(_ error: Error) -> String {
        let errStr = error.localizedDescription
        if errStr.contains("invalid credentials") || errStr.contains("401") {
            return "Invalid email address or password. Please verify and try again."
        } else if errStr.contains("already exists") || errStr.contains("409") {
            return "An account with this email address is already registered on our servers."
        } else if errStr.contains("network") || errStr.contains("connection") {
            return "Unable to connect to the authentication server. Please check your network connection."
        } else if errStr.contains("weak password") {
            return "Your password is too weak. Please ensure it is at least 8 characters long."
        }
        return errStr
    }
}

/// MARK: - Google and GitHub Branded Buttons

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
