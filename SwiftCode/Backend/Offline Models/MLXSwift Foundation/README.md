# MLXSwift Foundation Integration

This folder is now wired to Apple's **MLX Swift** ecosystem through Swift Package Manager in `SwiftCode.xcodeproj`.

## Integrated packages

The app target now links these products from [`ml-explore/mlx-swift`](https://github.com/ml-explore/mlx-swift):

- `MLX`
- `MLXNN`
- `MLXOptimizers`
- `MLXRandom`

## What changed

- `MLXIntegration.swift` now imports and validates runtime symbols from multiple MLX packages.
- `MLXModelContainer.swift` uses shared offline model/tokenizer protocols decoupled from any single model family loader.
- The Xcode project includes MLX Swift package references and product dependencies, so checkout/build resolves packages automatically (no manual package add steps required).

## Updating MLX Swift

1. Open `SwiftCode.xcodeproj` in Xcode.
2. Go to **Package Dependencies**.
3. Update `mlx-swift` to a newer compatible version.
4. Build the `SwiftCode` target and verify the Offline Models flow.

> Recommendation: update MLX packages and model-runtime adapter code together, because model-loading APIs may evolve between releases.

## Next step for model-family support

`UniversalModelLoader` now performs config-driven architecture detection (`model_type` in `config.json`), tokenizer discovery, and safetensors file resolution for both single-file and sharded layouts.

Architecture routing is now dynamic:

- `ArchitectureRegistry` normalizes and resolves architectures from `model_type`, not model names.
- Unknown/new model families are auto-registered at runtime to a generic transformer builder.
- Optional optimized builders can still be registered for known families over time.

The generic fallback reads transformer metadata from `config.json` (for example `hidden_size`, `num_hidden_layers`, and `num_attention_heads`) so newly added HuggingFace models can initialize without explicit hardcoded architecture entries.
