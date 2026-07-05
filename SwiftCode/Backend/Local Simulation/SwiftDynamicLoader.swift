import Foundation
import SwiftUI
import Darwin

final class SwiftDynamicLoader {
    private var activeHandle: UnsafeMutableRawPointer?

    func load(module: CompiledSimulationModule, entry: SimulationEntry) throws -> LoadedSimulation {
        unloadCurrentModule()

        guard let handle = dlopen(module.libraryURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let message = String(cString: dlerror())
            throw SimulationError(type: .load, message: "dlopen failed: \(message)", file: module.libraryURL.path, line: nil, stackTrace: nil)
        }

        activeHandle = handle

        let symbolName = "__swiftcode_make_root_view"
        guard let symbol = dlsym(handle, symbolName) else {
            return LoadedSimulation(
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

        return LoadedSimulation(anyView: view, hierarchyDescription: [resolvedName], handle: handle)
    }

    func unloadCurrentModule() {
        if let activeHandle {
            dlclose(activeHandle)
            self.activeHandle = nil
        }
    }
}
