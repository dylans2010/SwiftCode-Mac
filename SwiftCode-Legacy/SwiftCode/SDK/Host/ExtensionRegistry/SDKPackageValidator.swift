import Foundation

// MARK: - SDKPackageValidator
//
// Package-integrity validation for an extension directory (spec §7.2).
// Runs AFTER `SDKManifestValidator`: it checks the on-disk package against
// the already-validated manifest — entrypoint existence, path traversal,
// symlink containment, invalid names, unexpected executables, `.env` files,
// `node_modules`, and resource bounds.
//
// The manifest validator is pure; this validator performs the file walk.
// Thread-safe: static functions and value types only, no shared mutable state.

public enum SDKPackageValidator {

    // MARK: - Limits

    /// Maximum enumerated entries (files, directories, symlinks) per package.
    private static let maxWalkedEntries = 10_000
    /// Maximum total size of regular files per package.
    private static let maxTotalBytes: UInt64 = 100 * 1024 * 1024
    /// Maximum file-name length in bytes (matches common filesystem limits).
    private static let maxFileNameBytes = 255
    /// Cap on symlink indirections while resolving a single path.
    private static let maxSymlinkDepth = 40

    /// The v1 runtime is node loading a JS entrypoint — no executables of any
    /// kind are allowed inside a package.
    private static let executableExtensions: Set<String> = ["sh", "bin", "exe", "dylib", "so"]

    // MARK: - Entry point

    /// Validates the package at `root` against `manifest`.
    /// - Parameters:
    ///   - root: Package directory URL (must be a file URL).
    ///   - manifest: An already-validated `SDKManifest`.
    /// - Throws: `SDKError` on every rejection path.
    public static func validatePackage(at root: URL, manifest: SDKManifest) throws {
        let fileManager = FileManager.default

        guard root.isFileURL else {
            throw SDKError(
                code: .packageIntegrityFailure,
                message: "The extension package root is not a local directory.",
                suggestion: "Install the extension from a local directory on this Mac."
            )
        }
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        var rootIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedRoot.path, isDirectory: &rootIsDirectory),
              rootIsDirectory.boolValue else {
            throw SDKError(
                code: .packageIntegrityFailure,
                message: "The extension package directory is missing or not a directory.",
                suggestion: "Reinstall the extension package and try again."
            )
        }

        // The manifest file must be present at the package root.
        let manifestURL = try resolveContainedPath(relative: "swiftcode.json", under: resolvedRoot)
        var manifestIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: manifestURL.path, isDirectory: &manifestIsDirectory),
              !manifestIsDirectory.boolValue else {
            throw SDKError(
                code: .packageIntegrityFailure,
                message: "The package is missing swiftcode.json at its root.",
                suggestion: "Add a valid swiftcode.json manifest to the package root."
            )
        }

        // The entrypoint must resolve to a real file inside the package.
        // (Lexical checks already ran in the manifest validator; here symlinks
        // are resolved for real and containment is enforced.)
        let entryURL = try resolveContainedPath(relative: manifest.runtime.entrypoint, under: resolvedRoot)
        var entryIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: entryURL.path, isDirectory: &entryIsDirectory),
              !entryIsDirectory.boolValue else {
            throw SDKError(
                code: .packageIntegrityFailure,
                message: "The manifest entrypoint does not resolve to a file in the package.",
                suggestion: "Point \"runtime.entrypoint\" at the extension's built JS file inside the package."
            )
        }

        try walkPackage(root: resolvedRoot)
    }

    // MARK: - Contained path resolution

    /// Resolves a manifest-relative path against `root`, resolving symlinks
    /// component by component so an escaping link is caught before use.
    /// - Throws: `SDKError` with `.pathTraversal` on any escape.
    private static func resolveContainedPath(relative: String, under root: URL) throws -> URL {
        var current = root
        for rawComponent in relative.split(separator: "/") {
            let component = String(rawComponent)
            guard component != ".." else {
                throw traversal("A package path escapes the package root.")
            }
            current.appendPathComponent(component)

            var depth = 0
            while isSymbolicLink(current) {
                depth += 1
                guard depth <= maxSymlinkDepth else {
                    throw traversal("A package path contains a symlink loop.")
                }
                let target = try symlinkTarget(of: current)
                let resolved: URL
                if target.hasPrefix("/") {
                    resolved = URL(fileURLWithPath: target).standardizedFileURL
                } else {
                    resolved = current.deletingLastPathComponent()
                        .appendingPathComponent(target)
                        .standardizedFileURL
                }
                guard isWithin(resolved, root) else {
                    throw traversal("A symlink in the package points outside the package root.")
                }
                current = resolved
            }
            guard isWithin(current, root) else {
                throw traversal("A package path escapes the package root.")
            }
        }
        return current
    }

    private static func traversal(_ message: String) -> SDKError {
        SDKError(
            code: .pathTraversal,
            message: message,
            suggestion: "Keep every package path and symlink target inside the extension package directory."
        )
    }

    private static func isWithin(_ candidate: URL, _ root: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    private static func symlinkTarget(of url: URL) throws -> String {
        do {
            return try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
        } catch {
            throw SDKError(
                code: .packageIntegrityFailure,
                message: "The package contains an unreadable symlink.",
                suggestion: "Remove or repair broken symlinks in the package.",
                diagnostics: ["path": url.path]
            )
        }
    }

    // MARK: - Package walk

    private static func walkPackage(root: URL) throws {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        var ioError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, error in
                ioError = error
                return false // stop the walk rather than silently skipping
            }
        ) else {
            throw SDKError(
                code: .packageIntegrityFailure,
                message: "Could not read the extension package contents.",
                suggestion: "Check the package directory permissions and try again."
            )
        }

        var entryCount = 0
        var totalBytes: UInt64 = 0
        let rootPath = root.standardizedFileURL.path

        for case let url as URL in enumerator {
            entryCount += 1
            guard entryCount <= maxWalkedEntries else {
                throw SDKError(
                    code: .resourceLimitExceeded,
                    message: "The package contains more than 10,000 entries.",
                    suggestion: "Reduce the package contents to 10,000 files or fewer."
                )
            }

            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent

            // Invalid file names: null bytes or over-long names.
            if name.contains("\0") || name.utf8.count > maxFileNameBytes {
                throw SDKError(
                    code: .pathTraversal,
                    message: "The package contains a file with an invalid name.",
                    suggestion: "Rename package files to use names of 255 bytes or fewer with no control characters."
                )
            }

            // ".." segments must never appear in a walked path.
            let relativePath = relativePath(of: url, to: rootPath)
            if relativePath.split(separator: "/").contains("..") {
                throw traversal("The package contains a path that escapes the package root.")
            }

            // Symlinks: validate the target stays inside the root, then do
            // NOT descend (avoids loops and escape-via-directory-link).
            if values?.isSymbolicLink == true {
                try validateWalkedSymlink(at: url, rootPath: rootPath)
                enumerator.skipDescendants()
                continue
            }

            if values?.isDirectory == true {
                // v1 package format: no node_modules, even nested.
                if name == "node_modules" {
                    throw SDKError(
                        code: .packageIntegrityFailure,
                        message: "The package contains a node_modules directory.",
                        suggestion: "Ship the extension's compiled output without node_modules — the v1 package format does not allow it."
                    )
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }

            if let size = values?.fileSize, size >= 0 {
                totalBytes += UInt64(size)
                guard totalBytes <= maxTotalBytes else {
                    throw SDKError(
                        code: .resourceLimitExceeded,
                        message: "The package contents exceed the 100 MB limit.",
                        suggestion: "Reduce the package size to 100 MB or less."
                    )
                }
            }

            // Secrets must never ship inside a package.
            if name == ".env" || name.hasPrefix(".env.") {
                throw SDKError(
                    code: .packageIntegrityFailure,
                    message: "The package contains an environment (.env) file.",
                    suggestion: "Remove .env files from the package — secrets must never ship inside an extension package."
                )
            }

            // The v1 runtime is node loading a JS entrypoint: no executables.
            if executableExtensions.contains(url.pathExtension.lowercased()) {
                throw SDKError(
                    code: .packageIntegrityFailure,
                    message: "The package contains an unexpected executable file.",
                    suggestion: "Remove native binaries and scripts from the package — the v1 runtime loads a JS entrypoint with node only."
                )
            }
            if hasExecuteBit(url) {
                throw SDKError(
                    code: .packageIntegrityFailure,
                    message: "The package contains a file with the execute bit set.",
                    suggestion: "Remove the execute permission from package files — the v1 runtime does not execute package files directly."
                )
            }
        }

        if let ioError {
            throw SDKError(
                code: .packageIntegrityFailure,
                message: "Could not read the extension package contents.",
                suggestion: "Check the package directory permissions and try again.",
                diagnostics: ["ioError": String(describing: ioError)]
            )
        }
    }

    private static func validateWalkedSymlink(at url: URL, rootPath: String) throws {
        let target = try symlinkTarget(of: url)
        let resolved: String
        if target.hasPrefix("/") {
            resolved = URL(fileURLWithPath: target).standardizedFileURL.path
        } else {
            resolved = url.deletingLastPathComponent()
                .appendingPathComponent(target)
                .standardizedFileURL.path
        }
        guard resolved == rootPath || resolved.hasPrefix(rootPath + "/") else {
            throw SDKError(
                code: .pathTraversal,
                message: "A symlink in the package points outside the package root.",
                suggestion: "Make symlinks point to locations inside the extension package.",
                diagnostics: ["link": url.path]
            )
        }
    }

    private static func relativePath(of url: URL, to rootPath: String) -> String {
        let path = url.standardizedFileURL.path
        if path == rootPath { return "" }
        if path.hasPrefix(rootPath + "/") { return String(path.dropFirst(rootPath.count + 1)) }
        return path
    }

    private static func hasExecuteBit(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber else { return false }
        return permissions.intValue & 0o111 != 0
    }
}
