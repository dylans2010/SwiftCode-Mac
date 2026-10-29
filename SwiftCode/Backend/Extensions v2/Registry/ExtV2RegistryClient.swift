import Foundation

// MARK: - Open VSX registry client
//
// Uses the documented Open VSX REST API (https://open-vsx.org/swagger-ui/).
// Search:  GET {base}/-/search?query=&size=&offset=
// Details: GET {base}/{namespace}/{name}
// Download: files.download from the response, falling back to the
//           documented {base}/{namespace}/{name}/{version}/file/{file} form.
// No rating or download-count fields are mapped or displayed.

public struct ExtV2SearchPage: Sendable {
    public let results: [ExtV2ExtensionMetadata]
    public let total: Int
    public let offset: Int
    public let pageSize: Int

    public var hasMore: Bool { offset + results.count < total }
}

public final class ExtV2RegistryClient: Sendable {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = ExtV2ResourceLimits.registryTimeout
        config.timeoutIntervalForResource = ExtV2ResourceLimits.registryTimeout * 2
        self.session = URLSession(configuration: config)
    }

    public convenience init(settings: ExtV2Storage.Settings) {
        self.init(baseURL: URL(string: settings.registryBaseURL) ?? URL(string: "https://open-vsx.org/api")!)
    }

    // MARK: Search

    public func search(query: String, offset: Int = 0, pageSize: Int = 20) async throws -> ExtV2SearchPage {
        var components = URLComponents(url: baseURL.appendingPathComponent("-/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "size", value: String(pageSize)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        guard let url = components?.url else {
            throw ExtV2Error.registry("Could not build the registry search URL.")
        }
        let data = try await get(url: url)
        let page = try decodeSearch(data: data)
        return ExtV2SearchPage(results: page.results, total: page.total, offset: offset, pageSize: pageSize)
    }

    public func details(for identity: ExtV2Identity) async throws -> ExtV2ExtensionMetadata {
        let url = baseURL
            .appendingPathComponent(identity.publisher)
            .appendingPathComponent(identity.name)
        let data = try await get(url: url)
        return try decodeExtension(data: data)
    }

    /// Resolves a real download URL for the given version. Prefers the
    /// server-reported file URL; the constructed fallback is used only
    /// when the response omits it.
    public func downloadURL(for metadata: ExtV2ExtensionMetadata) async throws -> URL {
        if let direct = metadata.downloadURL { return direct }
        let detail = try await details(for: metadata.identity)
        if let direct = detail.downloadURL { return direct }
        let fileName = "\(metadata.publisher).\(metadata.name)-\(metadata.version).vsix"
        return baseURL
            .appendingPathComponent(metadata.publisher)
            .appendingPathComponent(metadata.name)
            .appendingPathComponent(metadata.version)
            .appendingPathComponent("file")
            .appendingPathComponent(fileName)
    }

    // MARK: Networking primitives

    private func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ExtV2Error.registry("Registry returned a non-HTTP response.")
            }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 404 {
                    throw ExtV2Error.registry("Extension not found in the registry.")
                }
                throw ExtV2Error.registry("Registry request failed with HTTP \(http.statusCode).")
            }
            return data
        } catch let error as ExtV2Error {
            throw error
        } catch is CancellationError {
            throw ExtV2Error.cancelled
        } catch {
            throw ExtV2Error.network("Registry request failed: \(error.localizedDescription)")
        }
    }

    /// Downloads a VSIX to a file (streamed by URLSession, not held fully
    /// in memory twice). The caller validates size again before extraction.
    public func downloadVSIX(from url: URL, to destination: URL) async throws {
        do {
            let (tempURL, response) = try await session.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ExtV2Error.network("Extension download failed.")
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
            guard size <= ExtV2ResourceLimits.maxVSIXBytes else {
                try? FileManager.default.removeItem(at: destination)
                throw ExtV2Error.package("Downloaded package exceeds the \(ExtV2ResourceLimits.maxVSIXBytes / 1024 / 1024) MB limit.")
            }
        } catch let error as ExtV2Error {
            throw error
        } catch is CancellationError {
            throw ExtV2Error.cancelled
        } catch {
            throw ExtV2Error.network("Extension download failed: \(error.localizedDescription)")
        }
    }

    // MARK: Decoding (tolerant: unknown registry fields are ignored)

    private struct SearchResponse: Decodable {
        var extensions: [ExtensionJSON]?
        var totalSize: Int?
        struct ExtensionJSON: Decodable {
            var namespace: String?
            var name: String?
            var version: String?
            var displayName: String?
            var description: String?
            var categories: [String]?
            var license: String?
            var homepage: String?
            var files: FilesJSON?
            struct FilesJSON: Decodable {
                var download: String?
            }
        }
    }

    private func decodeSearch(data: Data) throws -> (results: [ExtV2ExtensionMetadata], total: Int) {
        do {
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            let results = (decoded.extensions ?? []).compactMap { ext -> ExtV2ExtensionMetadata? in
                guard let namespace = ext.namespace, let name = ext.name,
                      let version = ext.version else { return nil }
                return ExtV2ExtensionMetadata(
                    publisher: namespace, name: name, version: version,
                    displayName: ext.displayName ?? name, description: ext.description ?? "",
                    categories: ext.categories ?? [], kind: .vscode,
                    license: ext.license, homepage: ext.homepage,
                    downloadURL: ext.files?.download.flatMap(URL.init(string:)))
            }
            return (results, decoded.totalSize ?? results.count)
        } catch {
            throw ExtV2Error.registry("Could not parse the registry search response: \(error.localizedDescription)")
        }
    }

    private func decodeExtension(data: Data) throws -> ExtV2ExtensionMetadata {
        do {
            let decoded = try JSONDecoder().decode(SearchResponse.ExtensionJSON.self, from: data)
            guard let namespace = decoded.namespace, let name = decoded.name,
                  let version = decoded.version else {
                throw ExtV2Error.registry("Registry details response is missing identity fields.")
            }
            return ExtV2ExtensionMetadata(
                publisher: namespace, name: name, version: version,
                displayName: decoded.displayName ?? name, description: decoded.description ?? "",
                categories: decoded.categories ?? [], kind: .vscode,
                license: decoded.license, homepage: decoded.homepage,
                downloadURL: decoded.files?.download.flatMap(URL.init(string:)))
        } catch let error as ExtV2Error {
            throw error
        } catch {
            throw ExtV2Error.registry("Could not parse the registry details response: \(error.localizedDescription)")
        }
    }
}
