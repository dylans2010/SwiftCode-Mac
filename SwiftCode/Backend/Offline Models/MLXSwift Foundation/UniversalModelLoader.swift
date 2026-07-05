import Foundation

struct UniversalLoadedModel {
    let model: OfflineLanguageModel
    let tokenizer: OfflineTokenizer
}

enum UniversalModelLoaderError: LocalizedError {
    case missingConfig(URL)
    case invalidConfig(URL)
    case missingModelType(URL)
    case missingWeights(URL)
    case invalidTokenizer(URL)
    case missingTokenizer(URL)
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .missingConfig(directory):
            return "Missing config.json in model directory: \(directory.path). Please check the model download and ensure HuggingFace files are complete."
        case let .invalidConfig(configURL):
            return "Could not parse config.json at: \(configURL.path)"
        case let .missingModelType(configURL):
            return "config.json is missing required field \"model_type\": \(configURL.path)"
        case let .missingWeights(directory):
            return "Missing model weights in \(directory.path). Expected .safetensors files (single or sharded). Please check the model download and retry."
        case let .invalidTokenizer(tokenizerURL):
            return "Tokenizer file is corrupt or unreadable: \(tokenizerURL.path)"
        case let .missingTokenizer(directory):
            return "Missing tokenizer in \(directory.path). Expected tokenizer.json or tokenizer.model (with tokenizer_config.json fallback). Please check the model download and retry."
        case let .runtimeUnavailable(details):
            return details
        }
    }
}

struct UniversalModelLoader {
    func loadModel(from directory: URL) async throws -> UniversalLoadedModel {
        let config = try loadConfig(from: directory)
        let architecture = ArchitectureRegistry.resolve(modelType: config.normalizedModelType)
        let tokenizer = try loadTokenizer(from: directory)
        let weights = try detectWeights(in: directory)

        ArchitectureRegistry.autoregisterIfNeeded(modelType: config.normalizedModelType)

        let model = try await architecture.buildModel(config: config, weightSource: weights)

        return UniversalLoadedModel(model: model, tokenizer: tokenizer)
    }

    private func loadConfig(from directory: URL) throws -> HuggingFaceModelConfig {
        let configURL = directory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw UniversalModelLoaderError.missingConfig(directory)
        }

        do {
            let data = try Data(contentsOf: configURL)
            let rawConfig = try JSONDecoder().decode(RawConfig.self, from: data)
            guard let modelType = rawConfig.modelType?.trimmingCharacters(in: .whitespacesAndNewlines), !modelType.isEmpty else {
                throw UniversalModelLoaderError.missingModelType(configURL)
            }

            return HuggingFaceModelConfig(modelDirectory: directory, modelType: modelType, rawJSON: data)
        } catch let error as UniversalModelLoaderError {
            throw error
        } catch {
            throw UniversalModelLoaderError.invalidConfig(configURL)
        }
    }

    private func loadTokenizer(from directory: URL) throws -> OfflineTokenizer {
        let tokenizerJSON = directory.appendingPathComponent("tokenizer.json")
        let tokenizerModel = directory.appendingPathComponent("tokenizer.model")
        let tokenizerConfig = directory.appendingPathComponent("tokenizer_config.json")

        if FileManager.default.fileExists(atPath: tokenizerJSON.path) {
            return try JSONBackedTokenizer.load(from: tokenizerJSON)
        }

        if FileManager.default.fileExists(atPath: tokenizerModel.path) {
            return FileBackedTokenizer(tokenizerFile: tokenizerModel)
        }

        if FileManager.default.fileExists(atPath: tokenizerConfig.path) {
            return try JSONBackedTokenizer.load(from: tokenizerConfig)
        }

        throw UniversalModelLoaderError.missingTokenizer(directory)
    }

    private func detectWeights(in directory: URL) throws -> WeightSource {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let safetensorFiles = contents
            .filter { $0.pathExtension.lowercased() == "safetensors" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        if safetensorFiles.count == 1, let single = safetensorFiles.first {
            return .single(single)
        }

        if !safetensorFiles.isEmpty {
            return .sharded(safetensorFiles)
        }

        throw UniversalModelLoaderError.missingWeights(directory)
    }
}

private struct RawConfig: Decodable {
    let modelType: String?

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
    }
}

struct HuggingFaceModelConfig {
    let modelDirectory: URL
    let modelType: String
    let rawJSON: Data

    var normalizedModelType: String {
        modelType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func value<T>(forAnyKey keys: [String], as type: T.Type = T.self) -> T? {
        guard
            let object = try? JSONSerialization.jsonObject(with: rawJSON),
            let dictionary = object as? [String: Any]
        else {
            return nil
        }

        for key in keys {
            if let value = dictionary[key] as? T {
                return value
            }
            if let number = dictionary[key] as? NSNumber, T.self == Int.self {
                return number.intValue as? T
            }
        }

        return nil
    }
}

enum WeightSource {
    case single(URL)
    case sharded([URL])

    var files: [URL] {
        switch self {
        case let .single(file):
            return [file]
        case let .sharded(files):
            return files
        }
    }
}

private enum ArchitectureRegistry {
    typealias Builder = (HuggingFaceModelConfig, WeightSource) async throws -> OfflineLanguageModel

    static func resolve(modelType: String) -> RegisteredArchitecture {
        let normalized = normalize(modelType)
        if let architecture = mapping[normalized] {
            return architecture
        }

        let fallback = RegisteredArchitecture(name: normalized, builder: GenericMLXArchitectureBuilders.generic)
        mapping[normalized] = fallback
        return fallback
    }

    static func autoregisterIfNeeded(modelType: String) {
        let normalized = normalize(modelType)
        guard mapping[normalized] == nil else { return }
        mapping[normalized] = RegisteredArchitecture(name: normalized, builder: GenericMLXArchitectureBuilders.generic)
    }

    static func register(modelTypes: [String], architectureName: String, builder: @escaping Builder) {
        let architecture = RegisteredArchitecture(name: normalize(architectureName), builder: builder)
        for modelType in modelTypes {
            mapping[normalize(modelType)] = architecture
        }
    }

    private static func normalize(_ modelType: String) -> String {
        modelType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static var mapping: [String: RegisteredArchitecture] = {
        var map: [String: RegisteredArchitecture] = [:]

        registerKnown(into: &map, aliases: ["llama", "mistral", "qwen", "phi", "gpt_neox", "falcon", "gemma"], builder: GenericMLXArchitectureBuilders.generic)

        return map
    }()

    private static func registerKnown(into map: inout [String: RegisteredArchitecture], aliases: [String], builder: @escaping Builder) {
        let name = aliases.first ?? "generic-transformer"
        let architecture = RegisteredArchitecture(name: name, builder: builder)
        for alias in aliases {
            map[normalize(alias)] = architecture
        }
    }
}

private struct RegisteredArchitecture {
    let name: String
    let builder: ArchitectureRegistry.Builder

    func buildModel(config: HuggingFaceModelConfig, weightSource: WeightSource) async throws -> OfflineLanguageModel {
        try await builder(config, weightSource)
    }
}

private enum GenericMLXArchitectureBuilders {
    static func generic(config: HuggingFaceModelConfig, weights: WeightSource) async throws -> OfflineLanguageModel {
        let transformerConfig = GenericTransformerConfig.from(config)
        return try GenericMLXTransformerLoader.buildModel(
            config: config,
            transformerConfig: transformerConfig,
            weights: weights
        )
    }
}

private struct GenericTransformerConfig {
    let hiddenSize: Int
    let numberOfHiddenLayers: Int
    let numberOfAttentionHeads: Int
    let vocabSize: Int

    static func from(_ config: HuggingFaceModelConfig) -> GenericTransformerConfig {
        GenericTransformerConfig(
            hiddenSize: config.value(forAnyKey: ["hidden_size", "n_embd", "d_model"], as: Int.self) ?? 0,
            numberOfHiddenLayers: config.value(forAnyKey: ["num_hidden_layers", "n_layer", "num_layers"], as: Int.self) ?? 0,
            numberOfAttentionHeads: config.value(forAnyKey: ["num_attention_heads", "n_head", "n_heads"], as: Int.self) ?? 0,
            vocabSize: config.value(forAnyKey: ["vocab_size"], as: Int.self) ?? 0
        )
    }
}

private enum GenericMLXTransformerLoader {
    static func buildModel(config: HuggingFaceModelConfig, transformerConfig: GenericTransformerConfig, weights: WeightSource) throws -> OfflineLanguageModel {
        let files = weights.files
        for file in files {
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw UniversalModelLoaderError.runtimeUnavailable(
                    "Model load failed for \(config.modelDirectory.path). Missing weight shard: \(file.lastPathComponent). Please verify your download and retry."
                )
            }
        }

        return GenericTransformerModel(
            architecture: config.normalizedModelType,
            config: transformerConfig,
            weightFiles: files
        )
    }
}

private struct GenericTransformerModel: OfflineLanguageModel {
    let architecture: String
    let config: GenericTransformerConfig
    let weightFiles: [URL]

    func generate(tokens: [Int]) -> AsyncThrowingStream<Int, Error> {
        AsyncThrowingStream { continuation in
            // Placeholder generic inference path: once MLX runtime adapters are linked,
            // this model can route through architecture-specific kernels.
            for token in tokens {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }
}

private struct JSONBackedTokenizer: OfflineTokenizer {
    let text: String

    static func load(from fileURL: URL) throws -> JSONBackedTokenizer {
        do {
            let data = try Data(contentsOf: fileURL)
            _ = try JSONSerialization.jsonObject(with: data)
            return JSONBackedTokenizer(text: String(decoding: data, as: UTF8.self))
        } catch {
            throw UniversalModelLoaderError.invalidTokenizer(fileURL)
        }
    }

    func encode(text: String) -> [Int] {
        Array(text.utf8).map(Int.init)
    }

    func decode(tokens: [Int]) -> String {
        let scalars = tokens.compactMap(UnicodeScalar.init).map(Character.init)
        return String(scalars)
    }
}

private struct FileBackedTokenizer: OfflineTokenizer {
    let tokenizerFile: URL

    func encode(text: String) -> [Int] {
        Array(text.utf8).map(Int.init)
    }

    func decode(tokens: [Int]) -> String {
        let scalars = tokens.compactMap(UnicodeScalar.init).map(Character.init)
        return String(scalars)
    }
}
