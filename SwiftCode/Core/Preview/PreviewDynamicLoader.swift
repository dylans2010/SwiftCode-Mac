import Foundation
import SwiftUI
import Darwin
import AppKit

/// Loads dynamically compiled SwiftUI libraries and extracts native interactive views.
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

        let symbolName = "__swiftcode_make_hosting_view"
        guard let symbol = dlsym(handle, symbolName) else {
            // Fallback to static descriptive container if dlsym is not found
            let fallbackView = AnyView(
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.amber)
                    Text("SwiftUI view loaded dynamically, but entry point is missing.")
                        .font(.subheadline)
                    Text(entry.rootViewType)
                        .font(.headline)
                }
                .padding()
            )
            return LoadedPreviewSimulation(
                anyView: fallbackView,
                hierarchyDescription: [entry.rootViewType],
                handle: handle
            )
        }

        typealias Factory = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
        let factory = unsafeBitCast(symbol, to: Factory.self)

        let resolvedName = entry.rootViewType
        guard let viewPtr = resolvedName.withCString({ factory($0) }) else {
            throw PreviewError.compilationError(details: "Failed to instantiate view '\(resolvedName)' from dylib.")
        }

        let hostingView = Unmanaged<NSView>.fromOpaque(viewPtr).takeRetainedValue()

        // Wrap the native view inside SwiftUI representation
        let wrappedView = AnyView(
            NativePreviewHost(hostedView: hostingView)
        )

        return LoadedPreviewSimulation(anyView: wrappedView, hierarchyDescription: [resolvedName], handle: handle)
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
