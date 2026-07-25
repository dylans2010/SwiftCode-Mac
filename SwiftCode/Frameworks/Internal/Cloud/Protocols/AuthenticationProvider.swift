import Foundation

public enum CloudAuthState: String, Codable, Sendable {
    case authenticated
    case unauthenticated
    case authenticating
    case error
}

public protocol AuthenticationProvider: AnyObject, Sendable {
    var authState: CloudAuthState { get }
    var currentUserEmail: String? { get }
    var currentUserID: String? { get }

    func signInWithEmail(email: String, password: String) async throws
    func signUpWithEmail(email: String, password: String) async throws
    func signInWithProvider(name: String) async throws
    func signInAnonymously() async throws
    func signOut() async throws
    func refreshSession() async throws
}
