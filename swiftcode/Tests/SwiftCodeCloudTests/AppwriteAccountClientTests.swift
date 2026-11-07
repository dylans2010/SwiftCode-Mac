import Foundation
import Testing
@testable import SwiftCodeCloud

struct AppwriteAccountClientTests {

    @Test("Session creation posts email/password and captures the session secret from Set-Cookie")
    func createEmailPasswordSession() async throws {
        let client = stubClient { request in
            if request.url?.path == "/v1/account/sessions/email" {
                return ok(sessionJSON, headers: sessionCookieHeader)
            }
            return ok("{}")
        }
        let session = try await client.createEmailPasswordSession(email: "dylan@example.com", password: "correct horse")
        #expect(session.id == "sess_1")
        #expect(session.userID == "user_1")
        #expect(session.provider == "email")
        #expect(session.current == true)
        #expect(client.sessionSecret == "stub-secret-123")

        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "POST")
        #expect(request?.value(forHTTPHeaderField: "X-Appwrite-Project") == "6a670d0b0022e5f964b4")
        let body = jsonBody(of: request!)
        #expect(body["email"] as? String == "dylan@example.com")
        #expect(body["password"] as? String == "correct horse")
    }

    @Test("Authenticated requests carry the session cookie")
    func authenticatedRequestCarriesCookie() async throws {
        let client = stubClient(initialSessionSecret: "stub-secret-123") { _ in ok(userJSON) }
        let user = try await client.getAccount()
        #expect(user.email == "dylan@example.com")
        #expect(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Cookie")
            == "a_session_6a670d0b0022e5f964b4=stub-secret-123")
    }

    @Test("getAccount without a session secret throws .missingSession and makes no request")
    func getAccountWithoutSession() async {
        let client = stubClient { _ in ok(userJSON) }
        await #expect(throws: AppwriteError.missingSession) {
            try await client.getAccount()
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("getAccount decodes the user, prefs, and verification flag")
    func getAccountDecodesUser() async throws {
        let client = stubClient(initialSessionSecret: "stub-secret-123") { _ in ok(userJSON) }
        let user = try await client.getAccount()
        #expect(user.id == "user_1")
        #expect(user.name == "Dylan")
        #expect(user.emailVerification == true)
        #expect(user.prefs["swiftcode_id"]?.stringValue == "sc_id=ABCDEF0123456789ABCDEF0123456789")
    }

    @Test("deleteSession deletes the current session and clears the secret")
    func deleteSession() async throws {
        let client = stubClient(initialSessionSecret: "stub-secret-123") { _ in ok("{}") }
        try await client.deleteSession(sessionId: "current")
        #expect(client.sessionSecret == nil)
        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "DELETE")
        #expect(request?.url?.path == "/v1/account/sessions/current")
    }

    @Test("createAccount posts userId unique() with email and password")
    func createAccount() async throws {
        let client = stubClient { _ in ok(userJSON) }
        let user = try await client.createAccount(userId: "unique()", email: "new@example.com", password: "s3cretpass")
        #expect(user.id == "user_1")
        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.path == "/v1/account")
        let body = jsonBody(of: request!)
        #expect(body["userId"] as? String == "unique()")
        #expect(body["email"] as? String == "new@example.com")
    }

    @Test("deleteAccount deletes the account and clears the secret")
    func deleteAccount() async throws {
        let client = stubClient(initialSessionSecret: "stub-secret-123") { _ in ok("{}") }
        try await client.deleteAccount()
        #expect(client.sessionSecret == nil)
        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "DELETE")
        #expect(request?.url?.path == "/v1/account")
    }

    @Test("updatePrefs patches the prefs object")
    func updatePrefs() async throws {
        let client = stubClient(initialSessionSecret: "stub-secret-123") { _ in ok(userJSON) }
        _ = try await client.updatePrefs(["swiftcode_id": "sc_id=0123456789ABCDEF0123456789ABCDEF"])
        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "PATCH")
        #expect(request?.url?.path == "/v1/account/prefs")
        let prefs = jsonBody(of: request!)["prefs"] as? [String: String]
        #expect(prefs?["swiftcode_id"]?.string == "sc_id=0123456789ABCDEF0123456789ABCDEF")
    }

    @Test("updateEmail patches the email with the password")
    func updateEmail() async throws {
        let client = stubClient(initialSessionSecret: "stub-secret-123") { _ in ok(userJSON) }
        _ = try await client.updateEmail(email: "other@example.com", password: "s3cretpass")
        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "PATCH")
        #expect(request?.url?.path == "/v1/account/email")
        let body = jsonBody(of: request!)
        #expect(body["email"] as? String == "other@example.com")
        #expect(body["password"] as? String == "s3cretpass")
    }

    @Test("updatePassword patches the password with the old password")
    func updatePassword() async throws {
        let client = stubClient(initialSessionSecret: "stub-secret-123") { _ in ok(userJSON) }
        _ = try await client.updatePassword(password: "n3wpassw0rd", oldPassword: "s3cretpass")
        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "PATCH")
        #expect(request?.url?.path == "/v1/account/password")
        let body = jsonBody(of: request!)
        #expect(body["password"] as? String == "n3wpassw0rd")
        #expect(body["oldPassword"] as? String == "s3cretpass")
    }

    @Test("createRecovery posts the email and redirect URL")
    func createRecovery() async throws {
        let client = stubClient { _ in ok("{}") }
        try await client.createRecovery(email: "dylan@example.com", url: "appwrite-callback-6a670d0b0022e5f964b4://reset-password")
        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.path == "/v1/account/recovery")
        let body = jsonBody(of: request!)
        #expect(body["email"] as? String == "dylan@example.com")
        #expect(body["url"] as? String == "appwrite-callback-6a670d0b0022e5f964b4://reset-password")
    }

    @Test("updateRecovery puts userId, secret, and the new password")
    func updateRecovery() async throws {
        let client = stubClient { _ in ok("{}") }
        try await client.updateRecovery(userId: "user_1", secret: "tok_123", password: "n3wpassw0rd")
        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "PUT")
        #expect(request?.url?.path == "/v1/account/recovery")
        let body = jsonBody(of: request!)
        #expect(body["userId"] as? String == "user_1")
        #expect(body["secret"] as? String == "tok_123")
    }

    @Test("createVerification posts the redirect URL")
    func createVerification() async throws {
        let client = stubClient { _ in ok("{}") }
        try await client.createVerification(url: "appwrite-callback-6a670d0b0022e5f964b4://verify")
        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.path == "/v1/account/verification")
        let body = jsonBody(of: request!)
        #expect(body["url"] as? String == "appwrite-callback-6a670d0b0022e5f964b4://verify")
    }

    @Test("updateVerification puts userId and secret")
    func updateVerification() async throws {
        let client = stubClient { _ in ok("{}") }
        try await client.updateVerification(userId: "user_1", secret: "tok_456")
        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "PUT")
        #expect(request?.url?.path == "/v1/account/verification")
        let body = jsonBody(of: request!)
        #expect(body["userId"] as? String == "user_1")
        #expect(body["secret"] as? String == "tok_456")
    }

    @Test("ping hits GET /ping and returns true on 2xx")
    func ping() async throws {
        let client = stubClient { _ in ok("{\"message\":\"pong\"}") }
        #expect(try await client.ping() == true)
        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "GET")
        #expect(request?.url?.path == "/v1/ping")
    }

    @Test("A 401 error body maps to .http and to the invalid-credentials sentence")
    func errorMapping401() async {
        let authed = stubClient(initialSessionSecret: "stale-secret") { _ in
            appwriteError(401, code: 401, type: "user_unauthorized", message: "Invalid `email` param: Invalid credentials")
        }
        do {
            _ = try await authed.getAccount()
            Issue.record("Expected a 401 error")
        } catch let appwriteError as AppwriteError {
            #expect(appwriteError == .http(status: 401, code: 401, type: "user_unauthorized", message: "Invalid `email` param: Invalid credentials"))
            #expect(appwriteError.userFacingMessage == "Invalid email address or password. Please verify and try again.")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("A 409 already-exists error maps to the registered-email sentence")
    func errorMapping409() async {
        let client = stubClient { _ in
            appwriteError(409, code: 409, type: "user_already_exists", message: "A user with the same email already exists")
        }
        do {
            _ = try await client.createAccount(userId: "unique()", email: "dylan@example.com", password: "s3cretpass")
            Issue.record("Expected a 409 error")
        } catch let appwriteError as AppwriteError {
            #expect(appwriteError.userFacingMessage == "An account with this email address is already registered on our servers.")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("A weak-password message maps to the weak-password sentence")
    func errorMappingWeakPassword() async {
        let client = stubClient { _ in
            appwriteError(400, code: 400, type: "user_password_mismatch", message: "Invalid `password` param: Password must be at least 8 characters")
        }
        do {
            _ = try await client.createAccount(userId: "unique()", email: "dylan@example.com", password: "short")
            Issue.record("Expected a 400 error")
        } catch let appwriteError as AppwriteError {
            #expect(appwriteError.userFacingMessage == "Your password is too weak. Please ensure it is at least 8 characters long.")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("OAuth authorize URL points at the Appwrite OAuth endpoint with project and callback")
    func oauthAuthorizeURL() {
        let client = AppwriteAccountClient()
        let url = client.oauthAuthorizeURL(provider: .google)
        #expect(url?.scheme == "https")
        #expect(url?.host == "sfo.cloud.appwrite.io")
        #expect(url?.path == "/v1/account/sessions/oauth2/google")
        let query = queryItems(of: URLRequest(url: url!))
        #expect(query["project"] == "6a670d0b0022e5f964b4")
        #expect(query["success"] == "appwrite-callback-6a670d0b0022e5f964b4://")
        #expect(query["failure"] == "appwrite-callback-6a670d0b0022e5f964b4://")
    }

    @Test("OAuth callback parsing distinguishes success, recovery, verification, and failure")
    func parseOAuthCallback() {
        let client = AppwriteAccountClient()
        #expect(client.parseOAuthCallback(URL(string: "appwrite-callback-6a670d0b0022e5f964b4://")!) == .success)
        #expect(client.parseOAuthCallback(URL(string: "appwrite-callback-6a670d0b0022e5f964b4://reset-password?userId=user_1&secret=tok_123")!)
            == .recovery(userId: "user_1", secret: "tok_123"))
        #expect(client.parseOAuthCallback(URL(string: "appwrite-callback-6a670d0b0022e5f964b4://verify?userId=user_1&secret=tok_456")!)
            == .verification(userId: "user_1", secret: "tok_456"))
        #expect(client.parseOAuthCallback(URL(string: "appwrite-callback-6a670d0b0022e5f964b4://?error=access_denied&error_description=Denied")!)
            == .failure(message: "Denied"))
        #expect(client.parseOAuthCallback(URL(string: "https://example.com/callback")!) == nil)
        #expect(client.parseOAuthCallback(URL(string: "appwrite-callback-otherproject://")!) == nil)
    }

    @Test("Storage listFiles decodes the file list")
    func storageListFiles() async throws {
        let client = stubClient(initialSessionSecret: "stub-secret-123") { _ in ok(filesJSON) }
        let files = try await client.listFiles(bucketId: "backups")
        #expect(files.count == 2)
        #expect(files[0].id == "file_a")
        #expect(files[0].name == "backup-a.zip")
        #expect(files[1].sizeOriginal == 456)
        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "GET")
        #expect(request?.url?.path == "/v1/storage/buckets/backups/files")
    }

    @Test("Storage download and delete hit the file endpoints")
    func storageDownloadDelete() async throws {
        let client = stubClient(initialSessionSecret: "stub-secret-123") { request in
            if request.url?.path.hasSuffix("/download") == true {
                return (200, [:], Data("zip-bytes".utf8))
            }
            return ok("{}")
        }
        let data = try await client.getFileDownload(bucketId: "backups", fileId: "file_a")
        #expect(String(data: data, encoding: .utf8) == "zip-bytes")
        try await client.deleteFile(bucketId: "backups", fileId: "file_a")
        let delete = StubURLProtocol.requests.last
        #expect(delete?.httpMethod == "DELETE")
        #expect(delete?.url?.path == "/v1/storage/buckets/backups/files/file_a")
    }
}
