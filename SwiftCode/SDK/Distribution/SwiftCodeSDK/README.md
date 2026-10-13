# SwiftCode SDK

SwiftCode SDK is the professional developer kit for building, automating, testing, and distributing native macOS applications, Swift packages, and SwiftCode extensions.

## Architecture & Modules
- **SwiftCodeSDK**: Root coordination, diagnostics, and environment discovery.
- **ProjectKit**: Native project automation, inspection, and generation.
- **BuildKit**: Compiler discovery, safe process orchestration, and diagnostic parsing.
- **SourceControlKit**: Git repository inspection and safe source control operations.
- **WorkspaceKit**: Safe file access, traversal prevention, and directory inspection.
- **DiagnosticsKit**: Standardized diagnostics engine with structured error codes.
- **ExtensionKit**: Extension lifecycle, capability enforcement, and packaging.

## Quick Start
Add the SDK `bin` directory to your PATH:
```bash
export PATH="/path/to/SwiftCodeSDK/bin:$PATH"
swiftcode-sdk doctor
```
Initialize a new extension:
```bash
swiftcode-sdk init typescript-extension MyExtension
swiftcode-sdk validate ./MyExtension
swiftcode-sdk package ./MyExtension --out ./dist
```
