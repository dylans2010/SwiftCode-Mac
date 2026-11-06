// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Offline Models/OfflineModelRunner.swift
//   (Legacy commit d51a8f0d)
//
// Runs an installed offline model end to end: conversion check, then
// load, then streaming generation. `OfflineModelConverter` is the
// destination's existing one (OfflineModelManager.swift) — it detects
// the on-disk layout and throws `OfflineModelError.conversionUnavailable`
// for GGUF, because no converter binary or MLX runtime exists here.
// Installed-model state itself lives in `OfflineModelManager` /
// `OfflineModelsStorage`; this runner does not keep a second registry.
//
// MLX GAP (see MLXIntegration.swift): `generateResponse` /
// `streamResponse` throw `MLXRuntimeError.runtimeUnavailable` through
// the loaded model until the MLX packages are added to Package.swift.
// The load path, the already-loaded fast path, and the streaming
// assembly are all real.
//
// Adaptation notes: Legacy was `ObservableObject` with an
// `NSError(domain: "OfflineModelRunner", code: 1, …)` for "no model
// loaded"; the destination uses `@Observable` and typed errors, so this
// follows that convention (`MLXRuntimeError.modelNotLoaded`).

import Foundation
import Observation

@MainActor
@Observable
public final class OfflineModelRunner {
    public static let shared = OfflineModelRunner()
    private init() {}

    private let container = MLXModelContainer()
    private var loadedModelPath: String?

    public var isModelLoaded: Bool { container.isLoaded }
    public var loadedModelName: String { container.modelName }

    public func loadModel(at url: URL) async throws {
        if loadedModelPath == url.path && container.isLoaded { return }

        try await OfflineModelConverter.shared.convertIfNecessary(at: url)
        try await container.loadModel(at: url)
        loadedModelPath = url.path
    }

    public func generateResponse(prompt: String) async throws -> String {
        var response = ""
        try await streamResponse(prompt: prompt) { token in
            response += token
        }
        return response
    }

    public func streamResponse(prompt: String, onToken: @escaping (String) -> Void) async throws {
        guard container.isLoaded else {
            throw MLXRuntimeError.modelNotLoaded
        }

        try await container.generate(prompt: prompt, onToken: onToken)
    }

    public func unloadModel() {
        container.reset()
        loadedModelPath = nil
    }
}
