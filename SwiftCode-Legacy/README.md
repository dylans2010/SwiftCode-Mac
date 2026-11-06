# SwiftCode

SwiftCode is a native macOS Integrated Development Environment (IDE) built with Swift 6 and SwiftUI. It features professional workspace components, local AI integration, SwiftUI previews, source control, and built-in developer tools.

---

## Table of Contents
1. [Architecture](#architecture)
2. [Key Subsystems](#key-subsystems)
3. [Directory Map](#directory-map)
4. [Services and Managers](#services-and-managers)
5. [Developer Guide](#developer-guide)
6. [FAQ](#faq)

---

## Architecture

SwiftCode uses a unidirectional, downward-only dependency model to ensure clean compile boundaries.

```
+-------------------------------------------------------------+
|                         VIEW (View)                         |
|         - SwiftUI Desktop-First Responsive Components       |
+------------------------------+------------------------------+
                               | (Reads / Observes)
                               v
+-------------------------------------------------------------+
|                     VIEWMODEL (ViewModel)                   |
|         - MainActor & Observable State Containers           |
+------------------------------+------------------------------+
                               | (Triggers operations)
                               v
+-------------------------------------------------------------+
|                     BACKEND & SERVICES                      |
|         - Actors (Network, Git, LLM Runners)                |
+------------------------------+------------------------------+
                               | (Operates on)
                               v
+-------------------------------------------------------------+
|                         CORE LAYER                          |
|         - Immutable Domain Models, Protocols & Enums        |
+-------------------------------------------------------------+
```

### Key Principles

1. **Strict Concurrency**: Every file compiles under Swift 6 strict concurrency checks. Shared state lives in actors or is isolated to `@MainActor`.
2. **Modern Observation**: Uses Swift's native `@Observable` macro instead of Combine or `ObservableObject`.
3. **Desktop-First Layout**: Adaptive layout engine replaces hardcoded frames to support responsive resizing.
4. **Keychain Security**: All private credentials and tokens are stored in the macOS Keychain.
5. **No Force Unwraps**: Use safe unwrapping. Any force-unwrap requires a `// SAFETY:` explanatory comment.

---

## Key Subsystems

### 1. Autonomous Agent and AI
* **Local LLMs**: Local model runner using MLX and Apple Intelligence.
* **Agent Orchestrator**: Runs an iterative execution loop (Plan, Implement, Validate).
* **Remote APIs**: Integrates with OpenRouter and Codex with real-time streaming.

### 2. Live Preview
* **SwiftRuntimeCompiler**: Compiles active files dynamically for previews.
* **LiveReloadManager**: Triggers instant re-renders upon saving file changes.
* **Web Preview**: Renders web content (HTML, JS, Markdown) inside a local WebKit view.

### 3. Git Integration
* **Local Git Service**: Runs Git commands for status, diffs, commits, and branch management.
* **GitHub Gists**: Full interface to list, create, and view Gist revisions.
* **PRs and Issues**: Renders pull requests and issues inside the sidebar.

### 4. Desktop UI Framework
Supports responsive macOS layout categories:
* **Compact**: Under 1024px width.
* **Regular**: 1024px to 1439px width.
* **Large**: 1440px to 1919px width.
* **Professional**: 1920px to 2559px width.
* **Ultra Wide**: 2560px and above.

Includes adaptive UI components: `AdaptivePage`, `AdaptiveGrid`, `AdaptiveSettingsPage`, `AdaptiveEditorPage`, and `AdaptiveSheet`.

### 5. Collaboration Hub
* **PeerSessionManager**: Shares workspaces with peers over local networks.
* **Conflict Resolver**: Interactive merge conflict UI.
* **Activity Log**: Monitors collaborator cursor positions and changes.

### 6. CI and Deployments
* **Deployments**: One-click deployments to Vercel, Netlify, and GitHub Pages.
* **Build Console**: Captures build logs and highlights compilation errors.

### 7. Developer Utilities
Over 90 built-in offline tools accessible from the toolbar:
* **Converters**: JSON/YAML, Case Converter, Hex-Decimal, and HTML Entity Converter.
* **Formatters**: XML Formatter, Minifiers, and String Escapers.
* **Generators**: UUIDs, Cron schedules, Random Strings, and CSS Shadow/Gradients.
* **Network**: Port scanner, WHOIS, IP lookup, and Webhook tester.

---

## Directory Map

```
SwiftCode/
├── App/           # Entry point and menu command configuration
├── Assets/        # App assets, themes, and icons
├── Backend/       # Git, AI, and deployment engines
├── Core/          # Domain models and core protocols
├── Features/      # Indexing and syntax parsing
├── Frameworks/    # Internal managers (package integrity, zip, plist, XML)
├── Models/        # Shared models and settings
├── Resources/     # Presets and code templates
├── Services/      # Singleton services (logging, keychain, highlighter)
├── Tools/         # Dev scripts and helpers
├── UI/            # Layout engines and styles
├── ViewModels/    # MainActor-isolated view models
└── Views/         # SwiftUI views and editor components
```

---

## Services and Managers

### Internal Managers (`Frameworks/Internal`)

| Class | Path | Responsibility |
| :--- | :--- | :--- |
| `ProjectCoordinator` | `ProjectCoordinator.swift` | Synchronizes loading and unloading states. |
| `ProjectIntegrityManager` | `ProjectIntegrityManager.swift` | Validates file package hashes to prevent corruption. |
| `ProjectSerializer` | `ProjectSerializer.swift` | Serializes project models to disk. |
| `ProjectDeserializer` | `ProjectDeserializer.swift` | Deserializes project models from disk. |
| `ProjectValidator` | `ProjectValidator.swift` | Audits files for target-specific compilation rules. |
| `ProjectPackageManager` | `ProjectPackageManager.swift` | Manages project-specific dependency paths. |
| `ProjectErrorManager` | `ProjectErrorManager.swift` | Tracks and exposes workspace errors in a central registry. |
| `ProjectJSONManager` | `ProjectJSONManager.swift` | Codec utility complying with Swift 6 strict concurrency. |
| `ProjectXMLManager` | `ProjectXMLManager.swift` | Parses XML assets, layouts, and legacy lists. |
| `ProjectPlistManager` | `ProjectPlistManager.swift` | Modifies configuration overrides inside Plist files. |
| `ProjectHashManager` | `ProjectHashManager.swift` | Standardizes workspace and file hashing. |
| `ProjectFileManager` | `ProjectFileManager.swift` | Performs basic folder creation and file write operations. |
| `ProjectMetadataManager` | `ProjectMetadataManager.swift` | Tracks metadata tags, file-count statistics, and dates. |
| `ProjectResourceManager` | `ProjectResourceManager.swift` | Binds and exposes resource files to compile targets. |
| `ProjectVersionManager` | `ProjectVersionManager.swift` | Validates API levels and manages migrations. |
| `ExportProjManager` | `ExportProjManager.swift` | Packages projects for export. |
| `ImportProjManager` | `ImportProjManager.swift` | Orchestrates project extraction and workspace registration. |
| `ManifestProjManager` | `ManifestProjManager.swift` | Validates manifest configurations. |

### App Services (`Services`)

| Service | Path | Responsibility |
| :--- | :--- | :--- |
| `CodingManager` | `Core/CodingManager.swift` | Safe atomic file operations preventing traversal attacks. |
| `ToolbarActionManager` | `Core/ToolbarActionManager.swift` | Handles toolbar and sidebar states. |
| `GitHubService` | `Services/GitHubService.swift` | Coordinates GitHub API integration. |
| `GitHubGistService` | `Backend/GitHub/GitHubGistService.swift` | Interfaces with GitHub Gists. |
| `OpenRouterService` | `Services/OpenRouterService.swift` | Connects to remote AI models using SSE streaming. |
| `KeychainService` | `Services/KeychainService.swift` | Securely stores secrets in the macOS Keychain. |
| `LocalModelManager` | `Services/LocalModelManager.swift` | Manages local MLX/CoreML model downloads. |
| `ZipImporter` | `Services/ZipImporter.swift` | Unzips workspace templates securely. |
| `ProjectTemplateManager` | `Services/ProjectTemplateManager.swift` | Scaffolds new projects from templates. |
| `ProjectFilesExtracter` | `Services/ProjectFilesExtracter.swift` | Assembles file trees for LLM prompts. |
| `ProjectBuilderManager` | `Services/ProjectBuilderManager.swift` | Invokes compiler and parses warnings/errors. |
| `LogManager` | `Services/LogManager.swift` | Replaces standard print with OS-native Logger. |
| `SyntaxHighlighter` | `Services/SyntaxHighlighter.swift` | Highlights syntax inside the editor views. |
| `CodeFormatter` | `Services/CodeFormatter.swift` | Re-formats and indents source code. |
| `CodeIndexService` | `Services/CodeIndexService.swift` | Maps symbol indexes to accelerate navigation. |
| `FolderManager` | `Services/FolderManager.swift` | Groups files inside the file tree. |
| `ExtensionManager` | `Services/ExtensionManager.swift` | Manages third-party plugins. |
| `PluginManager` | `Services/PluginManager.swift` | Runs script plugins in a secure sandbox. |
| `NotificationManager` | `Services/NotificationManager.swift` | Dispatches macOS notifications. |
| `RepoPermManager` | `Services/RepoPermManager.swift` | Governs authorization levels and permissions. |

---

## Developer Guide

### Getting Started

Requirements:
* **Operating System**: macOS 14.0 or newer.
* **Xcode**: Xcode 15.0 or newer (Xcode 16 recommended).
* **Git**: System Git installed.

```bash
# Clone the repository
git clone https://github.com/user/SwiftCode-Mac.git
cd SwiftCode-Mac

# Open the Xcode Project
open SwiftCode.xcodeproj
```

On first launch, SwiftCode will initialize:
1. `~/Documents/Projects/` to hold user workspaces.
2. `~/Documents/Models/` to store local AI weights.

### Xcode Project Integrity Protocol (`project.pbxproj`)

When adding or modifying Swift files, every file tracked in `project.pbxproj` must have exactly four coordinated entries to prevent target issues or project corruption:

1. **`PBXFileReference`**: Defines the physical file on disk.
2. **`PBXBuildFile`**: Connects the file reference to the build target system.
3. **`PBXSourcesBuildPhase`**: Registers the build file in the target compile sequence (under phase `9BF8BFB9B87ED46BDA700029`).
4. **`PBXGroup`**: Places the file reference in the target parent group array.

Every new UUID must be exactly 24 characters, uppercase hexadecimal, and completely unique.

---

## FAQ

#### Why are Combine, `@Published`, and `DispatchQueue` banned?
To comply with Swift 6 strict concurrency rules. Actors, `@MainActor` isolation, and `@Observable` are used instead.

#### How does the local AI offline model function?
It uses MLX Integration (`MLXSwift`) optimized for Apple Silicon. When offline, queries are processed locally.

#### Is there a test target to run?
No. Validation is performed through local simulation, compiler warning audits, and visual runtime verification.

#### How do I resolve a `cannot compile/load` error on local previews?
Verify your CLI path in settings and ensure your workspace path does not contain special characters.
