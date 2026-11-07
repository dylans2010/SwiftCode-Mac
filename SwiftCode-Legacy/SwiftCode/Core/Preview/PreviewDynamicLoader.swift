import Foundation
import SwiftUI
import Darwin
import AppKit

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
            let fallbackView = AnyView(
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.yellow)
                    Text("SwiftUI view loaded dynamically, but entry point is missing.")
                        .font(.subheadline)
                    Text(entry.rootViewType)
                        .font(.headline)
                }
                .padding()
            )
            let fallbackHostingView = NSHostingView(rootView: fallbackView)
            fallbackHostingView.translatesAutoresizingMaskIntoConstraints = false
            fallbackHostingView.autoresizingMask = [.width, .height]
            return LoadedPreviewSimulation(
                nativeView: fallbackHostingView,
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

        return LoadedPreviewSimulation(
            nativeView: hostingView,
            hierarchyDescription: [resolvedName],
            handle: handle
        )
    }

    public func unloadCurrentModule() {
        if let activeHandle {
            dlclose(activeHandle)
            self.activeHandle = nil
        }
    }
}

public struct LoadedPreviewSimulation: @unchecked Sendable {
    public let nativeView: NSView
    public let hierarchyDescription: [String]
    public let handle: UnsafeMutableRawPointer?
}
