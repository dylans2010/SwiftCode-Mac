#if canImport(AppKit)
import Foundation
import SwiftUI
import Darwin
import AppKit

public struct CompiledPreviewModule: Sendable {
    public let libraryURL: URL
    public let diagnostics: [String]
    public let metadata: [String: String]

    public init(libraryURL: URL, diagnostics: [String] = [], metadata: [String: String] = [:]) {
        self.libraryURL = libraryURL
        self.diagnostics = diagnostics
        self.metadata = metadata
    }
}

public final class PreviewDynamicLoader {
    private var activeHandle: UnsafeMutableRawPointer?

    public init() {}

    public func load(module: CompiledPreviewModule, entry: PreviewSimulationEntry, previewIndex: Int = 0) throws -> LoadedPreviewSimulation {
        unloadCurrentModule()

        guard let handle = dlopen(module.libraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let message = String(cString: dlerror())
            throw PreviewError.compilationError(details: "dlopen failed: \(message)")
        }

        activeHandle = handle

        if let view = try loadLegacyFactory(handle: handle, entry: entry) {
            return view
        }
        if let view = try loadDestinationFactory(handle: handle, entry: entry, previewIndex: previewIndex) {
            return view
        }

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

    private func loadLegacyFactory(handle: UnsafeMutableRawPointer, entry: PreviewSimulationEntry) throws -> LoadedPreviewSimulation? {
        guard let symbol = dlsym(handle, "__swiftcode_make_hosting_view") else { return nil }
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

    private func loadDestinationFactory(handle: UnsafeMutableRawPointer, entry: PreviewSimulationEntry, previewIndex: Int) throws -> LoadedPreviewSimulation? {
        guard let symbol = dlsym(handle, "swiftcode_preview_make") else { return nil }
        typealias Make = @convention(c) (Int32) -> UnsafeMutableRawPointer?
        let factory = unsafeBitCast(symbol, to: Make.self)

        guard let viewPtr = factory(Int32(previewIndex)) else {
            throw PreviewError.compilationError(details: "Failed to instantiate preview \(previewIndex) ('\(entry.rootViewType)') from dylib.")
        }

        let viewController = Unmanaged<NSViewController>.fromOpaque(viewPtr).takeRetainedValue()
        let hostingView = viewController.view
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.autoresizingMask = [.width, .height]

        return LoadedPreviewSimulation(
            nativeView: hostingView,
            hierarchyDescription: [entry.rootViewType],
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
#endif
