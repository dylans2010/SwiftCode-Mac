import Foundation

// MARK: - Open VSX registry client (spec §6.1)

public struct SearchPage: Sendable {
    public let results: [ExtensionMetadata]
    public let total: Int
    public let offset: Int
    public let pageSize: Int

    public var hasMore: Bool { offset + results.count < total }

    public init(results: [ExtensionMetadata], total: Int, offset: Int, pageSize: Int) {
        self.results = results
        self.total = total
        self.offset = offset
        self.pageSize = pageSize
    }
}

/// Real client for the Open VSX REST API. No authentication, no API key,
/// no account. `Accept: application/json`. Request timeout 30s, resource
/// timeout 60s. Download and install limits are the unified set
/// (64 MiB, deviation D-1).
public final class RegistryClient: Sendable {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = ResourceLimits.registryTimeout
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    public convenience init(settings: ExtensionSettings) {
        let base = URL(string: settings.registryBaseURL) ?? URL(string: "https://open-vsx.org/api")!
        self.init(baseURL: base)
    }

    private func get(path: String, query: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw YcodeExtensionError.registry("Invalid registry URL.") }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw YcodeExtensionError.network("Registry request failed: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw YcodeExtensionError.registry("Registry returned a non-HTTP response.")
        }
        if http.statusCode == 404 {
            throw YcodeExtensionError.registry("Extension not found in the registry.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw YcodeExtensionError.registry("Registry request failed with HTTP \(http.statusCode).")
        }
        return (data, http)
    }

    public func search(query: String, offset: Int = 0, pageSize: Int = 20) async throws -> SearchPage {
        let (data, _) = try await get(path: "-/search", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "size", value: "\(pageSize)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
        ])
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YcodeExtensionError.registry("Registry search response was unparseable.")
        }
        let rawExtensions = object["extensions"] as? [[String: Any]] ?? []
        let results = rawExtensions.compactMap { Self.metadata(from: $0) }
        let total = object["totalSize"] as? Int ?? results.count
        return SearchPage(results: results, total: total, offset: offset, pageSize: pageSize)
    }

    public func details(for identity: ExtensionIdentity) async throws -> ExtensionMetadata {
        let (data, _) = try await get(path: "\(identity.publisher)/\(identity.name)")
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = Self.metadata(from: object) else {
            throw YcodeExtensionError.registry("Registry details response was unparseable.")
        }
        return metadata
    }

    public func downloadURL(for metadata: ExtensionMetadata) async throws -> URL {
        if let downloadURL = metadata.downloadURL { return downloadURL }
        let detailed = try await details(for: metadata.identity)
        if let downloadURL = detailed.downloadURL { return downloadURL }
        // Constructed fallback (spec §6.1).
        return baseURL
            .appendingPathComponent(metadata.publisher)
            .appendingPathComponent(metadata.name)
            .appendingPathComponent(metadata.version)
            .appendingPathComponent("file")
            .appendingPathComponent("\(metadata.publisher).\(metadata.name)-\(metadata.version).vsix")
    }

    /// Streams the VSIX to `destination`. Over the 64 MiB unified limit
    /// the file is deleted and a package error is thrown (D-1).
    public func downloadVSIX(from url: URL, to destination: URL) async throws {
        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(from: url)
        } catch is CancellationError {
            throw YcodeExtensionError.cancelled
        } catch {
            throw YcodeExtensionError.network("Registry download failed: \(error.localizedDescription)")
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            try? FileManager.default.removeItem(at: tempURL)
            throw YcodeExtensionError.registry("Extension not found in the registry.")
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: tempURL)
            throw YcodeExtensionError.registry("Registry request failed with HTTP \(http.statusCode).")
        }
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            if size > ResourceLimits.maxVSIXBytes {
                try? FileManager.default.removeItem(at: destination)
                throw YcodeExtensionError.package("VSIX exceeds the 64 MiB limit.")
            }
        } catch let error as YcodeExtensionError {
            throw error
        } catch {
            throw YcodeExtensionError.package("Could not store the downloaded VSIX: \(error.localizedDescription)")
        }
    }

    static func metadata(from dict: [String: Any]) -> ExtensionMetadata? {
        guard let namespace = dict["namespace"] as? String,
              let name = dict["name"] as? String,
              let version = dict["version"] as? String else {
            return nil // Rows missing namespace/name/version are dropped.
        }
        let files = dict["files"] as? [String: Any]
        let download = (files?["download"] as? String).flatMap { URL(string: $0) }
        return ExtensionMetadata(
            publisher: namespace, name: name, version: version,
            displayName: dict["displayName"] as? String ?? name,
            description: dict["description"] as? String ?? "",
            categories: dict["categories"] as? [String] ?? [],
            kind: .vscode,
            license: dict["license"] as? String,
            homepage: dict["homepage"] as? String,
            downloadURL: download,
            engineRequirement: (dict["engines"] as? [String: Any])?["vscode"] as? String)
    }
}

// MARK: - Dependency resolution (spec §6.4, pure, no IO)

public struct DependencyResolution: Sendable {
    public let installOrder: [String]
    public let missing: [String]
    public let cycles: [[String]]

    public var isSatisfied: Bool { missing.isEmpty && cycles.isEmpty }

    public init(installOrder: [String], missing: [String], cycles: [[String]]) {
        self.installOrder = installOrder
        self.missing = missing
        self.cycles = cycles
    }
}

public enum DependencyResolver {
    /// Topological order (dependencies first). A dependency is
    /// satisfied only by an installed extension or one in the same
    /// batch — never by assuming the registry will provide it later.
    /// Cycles are reported as the stack slice plus the repeated id;
    /// missing ids are de-duplicated in order of first sight.
    public static func resolve(requested: [VSCodeManifest], installedIDs: Set<String>,
                               manifestsByID: [String: VSCodeManifest]) -> DependencyResolution {
        var order: [String] = []
        var missing: [String] = []
        var seenMissing: Set<String> = []
        var cycles: [[String]] = []
        var visited: Set<String> = []
        var stack: [String] = []

        func visit(_ id: String, manifest: VSCodeManifest?) {
            if visited.contains(id) { return }
            if let index = stack.firstIndex(of: id) {
                cycles.append(Array(stack[index...]) + [id])
                return
            }
            stack.append(id)
            defer { stack.removeLast() }
            for dependency in manifest?.allDependencies ?? [] {
                if installedIDs.contains(dependency) || manifestsByID[dependency] != nil {
                    if let depManifest = manifestsByID[dependency] {
                        visit(dependency, manifest: depManifest)
                    }
                } else if seenMissing.insert(dependency).inserted {
                    missing.append(dependency)
                }
            }
            visited.insert(id)
            order.append(id)
        }

        for manifest in requested {
            visit(manifest.identity.id, manifest: manifest)
        }
        return DependencyResolution(installOrder: order, missing: missing, cycles: cycles)
    }

    /// Every declared dependency must be installed **and enabled**; a
    /// disabled dependency counts as missing.
    public static func missingDependencies(for installed: InstalledExtension,
                                           installedByID: [String: InstalledExtension]) -> [String] {
        installed.dependencies.filter { dependency in
            guard let record = installedByID[dependency] else { return true }
            return !record.isEnabled
        }
    }
}
