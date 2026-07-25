import Foundation
import os.log

public final class SupabaseCloudProvider: NSObject, CloudProvider, SyncProvider, BackupProvider, StorageProvider, Sendable {
    public let type: CloudProviderType = .supabase
    public let isEnabled: Bool = true
    public let name: String = "SwiftCode Cloud (Supabase)"

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "SupabaseProvider")
    private let urlSession: URLSession = URLSession(configuration: .default)

    public override init() {
        super.init()
    }

    public func initialize() async throws {
        logger.info("Initializing Supabase Cloud Provider...")
    }

    public func testConnection() async -> Bool {
        let auth = await SupabaseAuthService.shared
        let urlStr = auth.supabaseURL
        let anonKey = auth.supabaseAnonKey

        guard let url = URL(string: "\(urlStr)/rest/v1/") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        do {
            let (_, response) = try await urlSession.data(for: request)
            if let httpRes = response as? HTTPURLResponse {
                // Any status code indicates the URL endpoint was reachable
                return (200...499).contains(httpRes.statusCode)
            }
            return false
        } catch {
            logger.error("Connection test failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - SyncProvider (Database table syncing using PostgREST)

    public func pushChanges(_ payloads: [SyncPayload]) async throws -> [String] {
        let auth = await SupabaseAuthService.shared
        let urlStr = auth.supabaseURL
        let anonKey = auth.supabaseAnonKey
        let token = auth.accessToken ?? anonKey

        var succeededIDs: [String] = []

        for payload in payloads {
            guard let url = URL(string: "\(urlStr)/rest/v1/\(payload.table)") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

            // Parse existing json payload data
            if let jsonObj = try? JSONSerialization.jsonObject(with: payload.data) as? [String: Any] {
                var modifiedObj = jsonObj
                // Inject owner profile id if missing and authenticated
                if let uid = auth.currentUserID {
                    modifiedObj["owner_id"] = uid
                }
                request.httpBody = try? JSONSerialization.data(withJSONObject: [modifiedObj])
            } else {
                request.httpBody = payload.data
            }

            do {
                let (_, response) = try await urlSession.data(for: request)
                if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                    succeededIDs.append(payload.resourceID)
                } else {
                    logger.warning("Failed to push record for \(payload.table): \(payload.resourceID)")
                }
            } catch {
                logger.error("Error pushing payload \(payload.resourceID): \(error.localizedDescription, privacy: .public)")
            }
        }
        return succeededIDs
    }

    public func pullChanges(since lastSync: Date) async throws -> [SyncPayload] {
        let auth = await SupabaseAuthService.shared
        let urlStr = auth.supabaseURL
        let anonKey = auth.supabaseAnonKey
        let token = auth.accessToken ?? anonKey

        // Pull updates from standard sync tables: projects, settings, snippets, chat_history
        let tables = ["projects", "settings", "snippets", "chat_history"]
        var fetchedPayloads: [SyncPayload] = []

        let dateFormatter = ISO8601DateFormatter()
        let formattedDate = dateFormatter.string(from: lastSync)

        for table in tables {
            let endpoint = "\(urlStr)/rest/v1/\(table)?updated_at=gt.\(formattedDate)"
            guard let url = URL(string: endpoint) else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { continue }

                if let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    for record in records {
                        let resourceID = (record["id"] as? String) ?? UUID().uuidString
                        let rawData = try JSONSerialization.data(withJSONObject: record)
                        let lastMod = (record["updated_at"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()

                        let payload = SyncPayload(
                            resourceID: resourceID,
                            table: table,
                            data: rawData,
                            lastModified: lastMod,
                            version: (record["version"] as? Int) ?? 1
                        )
                        fetchedPayloads.append(payload)
                    }
                }
            } catch {
                logger.error("Error pulling \(table): \(error.localizedDescription, privacy: .public)")
            }
        }

        return fetchedPayloads
    }

    // MARK: - BackupProvider (Supabase Storage archive management)

    public func uploadBackup(archiveData: Data, filename: String, manifestJSON: String) async throws {
        // First upload file to the bucket
        _ = try await uploadFile(bucket: "backups", path: filename, data: archiveData, contentType: "application/zip")

        // Next register the backup record in the metadata table
        let auth = await SupabaseAuthService.shared
        let urlStr = auth.supabaseURL
        let anonKey = auth.supabaseAnonKey
        let token = auth.accessToken ?? anonKey

        guard let url = URL(string: "\(urlStr)/rest/v1/backups") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        var manifestDict: [String: Any] = [:]
        if let data = manifestJSON.data(using: .utf8) {
            manifestDict = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }

        let body: [String: Any] = [
            "filename": filename,
            "size_bytes": archiveData.count,
            "manifest": manifestDict,
            "owner_id": auth.currentUserID ?? ""
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: [body])
        _ = try? await urlSession.data(for: request)
    }

    public func downloadBackup(filename: String) async throws -> (Data, String) {
        let fileData = try await downloadFile(bucket: "backups", path: filename)

        // Retrieve manifest details from metadata table
        let auth = await SupabaseAuthService.shared
        let urlStr = auth.supabaseURL
        let anonKey = auth.supabaseAnonKey
        let token = auth.accessToken ?? anonKey

        var manifestString = "{}"
        let endpoint = "\(urlStr)/rest/v1/backups?filename=eq.\(filename)"
        if let url = URL(string: endpoint) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")

            if let (data, response) = try? await urlSession.data(for: request),
               let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let record = list.first,
               let manifest = record["manifest"] as? [String: Any],
               let manifestData = try? JSONSerialization.data(withJSONObject: manifest),
               let manifestStr = String(data: manifestData, encoding: .utf8) {
                manifestString = manifestStr
            }
        }

        return (fileData, manifestString)
    }

    public func listBackups() async throws -> [String] {
        let auth = await SupabaseAuthService.shared
        let urlStr = auth.supabaseURL
        let anonKey = auth.supabaseAnonKey
        let token = auth.accessToken ?? anonKey

        guard let url = URL(string: "\(urlStr)/rest/v1/backups?select=filename") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { return [] }

        if let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return records.compactMap { $0["filename"] as? String }
        }
        return []
    }

    public func deleteBackup(filename: String) async throws {
        try await deleteFile(bucket: "backups", path: filename)

        // Remove DB metadata entry
        let auth = await SupabaseAuthService.shared
        let urlStr = auth.supabaseURL
        let anonKey = auth.supabaseAnonKey
        let token = auth.accessToken ?? anonKey

        guard let url = URL(string: "\(urlStr)/rest/v1/backups?filename=eq.\(filename)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        _ = try? await urlSession.data(for: request)
    }

    // MARK: - StorageProvider (Supabase Storage direct REST uploads/downloads)

    public func uploadFile(bucket: String, path: String, data: Data, contentType: String) async throws -> URL {
        let auth = await SupabaseAuthService.shared
        let urlStr = auth.supabaseURL
        let anonKey = auth.supabaseAnonKey
        let token = auth.accessToken ?? anonKey

        // Create specific upload endpoint
        let endpoint = "\(urlStr)/storage/v1/object/\(bucket)/\(path)"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (resData, response) = try await urlSession.data(for: request)
        guard let httpRes = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // If file already exists, attempt a PUT overwrite
        if httpRes.statusCode == 400 || httpRes.statusCode == 409 {
            var overwriteRequest = URLRequest(url: url)
            overwriteRequest.httpMethod = "PUT"
            overwriteRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            overwriteRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
            overwriteRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            overwriteRequest.httpBody = data

            let (_, overwriteResponse) = try await urlSession.data(for: overwriteRequest)
            guard let finalRes = overwriteResponse as? HTTPURLResponse, (200...299).contains(finalRes.statusCode) else {
                throw NSError(domain: "SupabaseStorage", code: finalRes.statusCode, userInfo: [NSLocalizedDescriptionKey: "Overwriting storage asset failed"])
            }
        } else if !(200...299).contains(httpRes.statusCode) {
            let desc = String(data: resData, encoding: .utf8) ?? "Upload request failed"
            throw NSError(domain: "SupabaseStorage", code: httpRes.statusCode, userInfo: [NSLocalizedDescriptionKey: desc])
        }

        let publicURLString = "\(urlStr)/storage/v1/object/public/\(bucket)/\(path)"
        return URL(string: publicURLString)!
    }

    public func downloadFile(bucket: String, path: String) async throws -> Data {
        let auth = await SupabaseAuthService.shared
        let urlStr = auth.supabaseURL
        let anonKey = auth.supabaseAnonKey
        let token = auth.accessToken ?? anonKey

        let endpoint = "\(urlStr)/storage/v1/object/\(bucket)/\(path)"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            throw NSError(domain: "SupabaseStorage", code: code, userInfo: [NSLocalizedDescriptionKey: "Download failed"])
        }

        return data
    }

    public func deleteFile(bucket: String, path: String) async throws {
        let auth = await SupabaseAuthService.shared
        let urlStr = auth.supabaseURL
        let anonKey = auth.supabaseAnonKey
        let token = auth.accessToken ?? anonKey

        let endpoint = "\(urlStr)/storage/v1/object/\(bucket)/\(path)"
        guard let url = URL(string: endpoint) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        let (_, response) = try await urlSession.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            throw NSError(domain: "SupabaseStorage", code: code, userInfo: [NSLocalizedDescriptionKey: "Deletion failed"])
        }
    }
}
