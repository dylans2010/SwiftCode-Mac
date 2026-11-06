import Foundation

// MARK: - Dependency resolution (pure, testable, no I/O)

public struct ExtV2DependencyResolution: Sendable {
    public let installOrder: [String]
    public let missing: [String]
    public let cycles: [[String]]

    public var isSatisfied: Bool { missing.isEmpty && cycles.isEmpty }
}

/// Resolves `extensionDependencies` + `extensionPack` against the installed
/// set plus the batch being installed. A dependency is satisfied only by
/// an installed extension or one in the same batch — never by assuming
/// the registry will provide it later.
public enum ExtV2DependencyResolver {
    public static func resolve(
        requested: [ExtV2VSCodeManifest],
        installedIDs: Set<String>,
        manifestsByID: [String: ExtV2VSCodeManifest]
    ) -> ExtV2DependencyResolution {
        var missing: [String] = []
        var cycles: [[String]] = []
        var order: [String] = []
        var visited: Set<String> = []
        var stack: [String] = []

        func visit(_ id: String) {
            if visited.contains(id) { return }
            if let index = stack.firstIndex(of: id) {
                cycles.append(Array(stack[index...]) + [id])
                return
            }
            stack.append(id)
            defer { stack.removeLast() }
            if let manifest = manifestsByID[id] {
                for dep in manifest.allDependencies {
                    if installedIDs.contains(dep) || manifestsByID[dep] != nil {
                        visit(dep)
                    } else if !missing.contains(dep) {
                        missing.append(dep)
                    }
                }
            }
            visited.insert(id)
            order.append(id)
        }

        for manifest in requested {
            visit(manifest.identity.id)
        }
        return ExtV2DependencyResolution(installOrder: order, missing: missing, cycles: cycles)
    }

    /// Convenience check used by the manager before activation: every
    /// declared dependency must already be installed and enabled.
    public static func missingDependencies(
        for installed: ExtV2InstalledExtension,
        installedByID: [String: ExtV2InstalledExtension]
    ) -> [String] {
        installed.dependencies.filter { dep in
            guard let found = installedByID[dep] else { return true }
            return !found.isEnabled
        }
    }
}
