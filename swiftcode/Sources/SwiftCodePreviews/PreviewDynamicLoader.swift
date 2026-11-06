#if canImport(AppKit)
import Foundation
import SwiftUI
import Darwin
import AppKit

/// A compiled preview module: the dylib the preview compiler
/// produced, plus its diagnostics and metadata. (Legacy's
/// `CompiledPreviewModule`; the type did not exist in the
/// destination, so it is defined here with the fields the loader
/// and runtime use.)
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

/// Loads dynamically compiled SwiftUI libraries and extracts native
/// interactive views (Legacy
/// `SwiftCode/Core/Preview/PreviewDynamicLoader.swift`, Dylan's own
/// code, ported under MIT). Direct port, with one adaptation: the
/// destination's payload compiler exports `swiftcode_preview_make`
/// (preview index → NSViewController, see `PreviewMacHost`) instead
/// of Legacy's `__swiftcode_make_hosting_view` (view type name →
/// NSView), so the loader tries the Legacy symbol first and the
/// destination's symbol second (preview index 0 by default). The
/// whole file is AppKit only (`NSHostingView` / `NSView`), so it
/// compiles to nothing on Linux, matching the destination's
/// cross-platform `SwiftCodePreviews` target.
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

        // Legacy's compiler exported `__swiftcode_make_hosting_view`
        // (view type name → NSView). The destination's payload
        // compiler exports `swiftcode_preview_make` instead (preview
        // index → NSViewController, see `PreviewMacHost`); try the
        // Legacy symbol first, then the destination's.
        if let view = try loadLegacyFactory(handle: handle, entry: entry) {
            return view
        }
        if let view = try loadDestinationFactory(handle: handle, entry: entry, previewIndex: previewIndex) {
            return view
        }

        // Fallback to static descriptive container if no entry point is found
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

    /// Legacy's name-based factory: `__swiftcode_make_hosting_view`
    /// (view type name → retained NSView). Returns nil when the
    /// dylib has no such symbol.
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

    /// The destination payload factory: `swiftcode_preview_make`
    /// (preview index → retained NSViewController). Returns nil when
    /// the dylib has no such symbol.
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

// SAFETY JUSTIFICATION: LoadedPreviewSimulation is used purely for UI observation/rendering
// and runtime dynamic linking handle cleanup on the @MainActor thread. Its properties
// are only accessed and mutated on @MainActor, ensuring thread safety.
public struct LoadedPreviewSimulation: @unchecked Sendable {
    public let nativeView: NSView
    public let hierarchyDescription: [String]
    public let handle: UnsafeMutableRawPointer?
}
#endif
