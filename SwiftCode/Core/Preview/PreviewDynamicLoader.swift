import Foundation
import SwiftUI
import Darwin

public final class PreviewDynamicLoader {
    private var activeHandle: UnsafeMutableRawPointer?

    public init() {}

    public func load(module: CompiledPreviewModule, entry: PreviewSimulationEntry) throws -> LoadedPreviewSimulation {
        unloadCurrentModule()

        guard let handle = dlopen(module.libraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let message = String(cString: dlerror())
            throw PreviewError.compilationError(details: "dlopen failed: \(message)")
        }

        activeHandle = handle

        let symbolName = "__swiftcode_make_root_view"
        guard let symbol = dlsym(handle, symbolName) else {
            return LoadedPreviewSimulation(
                anyView: AnyView(Text(entry.rootViewType).padding()),
                hierarchyDescription: [entry.rootViewType],
                handle: handle
            )
        }

        typealias Factory = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
        let factory = unsafeBitCast(symbol, to: Factory.self)
        let resolvedNamePtr = entry.rootViewType.withCString { pointer in
            factory(pointer)
        }
        let resolvedName = resolvedNamePtr.map { String(cString: $0) } ?? entry.rootViewType
        resolvedNamePtr.map { free($0) }

        let view = AnyView(
            VStack(spacing: 10) {
                Text("Runtime Loaded")
                    .font(.headline)
                Text(resolvedName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
        )

        return LoadedPreviewSimulation(anyView: view, hierarchyDescription: [resolvedName], handle: handle)
    }

    public func unloadCurrentModule() {
        if let activeHandle {
            dlclose(activeHandle)
            self.activeHandle = nil
        }
    }
}

// SAFETY JUSTIFICATION: LoadedPreviewSimulation is used purely for UI observation/rendering
// and runtime dynamic linking handle cleanup on the @MainActor thread. Its properties
// are only accessed and mutated on @MainActor, ensuring thread safety.
public struct LoadedPreviewSimulation: @unchecked Sendable {
    public let anyView: AnyView
    public let hierarchyDescription: [String]
    public let handle: UnsafeMutableRawPointer?
}
