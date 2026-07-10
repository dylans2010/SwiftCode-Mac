# SwiftCode — Native macOS Integrated Development Environment (IDE)

SwiftCode is a next-generation, native macOS Integrated Development Environment (IDE) written entirely in **Swift 6** using **SwiftUI**. Designed for the modern Apple silicon era, SwiftCode blends traditional, high-density professional workspace components with state-of-the-art agentic workflows, on-device AI integration, instant SwiftUI preview simulations, unified source control, and a rich, desktop-optimized tool suite.

---

## 🗺️ Table of Contents
1. [🏗️ Architecture & Core Principles](#-architecture--core-principles)
   - [Architectural Layers](#architectural-layers)
   - [Design Guidelines & Concurrency Rules](#design-guidelines--concurrency-rules)
2. [🖥️ Key Subsystems & Features](#️-key-subsystems--features)
   - [1. Autonomous Agent & On-Device AI](#1-autonomous-agent--on-device-ai)
   - [2. Local Simulation & Live Preview](#2-local-simulation--live-preview)
   - [3. Git Integration & Source Control](#3-git-integration--source-control)
   - [4. Professional Desktop UI Framework](#4-professional-desktop-ui-framework)
   - [5. Collaboration Hub](#5-collaboration-hub)
   - [6. Deployments & Continuous Integration](#6-deployments--continuous-integration)
   - [7. Massive Dev Tools Suite](#7-massive-dev-tools-suite)
3. [📂 Directory Map](#-directory-map)
4. [🛠️ Manager & Service Catalog](#️-manager--service-catalog)
   - [Internal Framework Managers (`Frameworks/Internal`)](#internal-framework-managers-frameworksinternal)
   - [App Services (`Services`)](#app-services-services)
5. [🧑‍💻 Developer Guide: Cloning & Contributing](#-developer-guide-cloning--contributing)
   - [Getting Started](#getting-started)
   - [The Xcode Project File Integrity Protocol (`project.pbxproj`)](#the-xcode-project-file-integrity-protocol-projectpbxproj)
6. [❓ Frequently Asked Questions (FAQs)](#-frequently-asked-questions-faqs)

---

## 🏗️ Architecture & Core Principles

SwiftCode enforces strict architectural layering to prevent spaghetti dependencies and guarantee clean compile boundaries. All components follow a unidirectional, downward-only dependency model.

### Architectural Layers

```
+-------------------------------------------------------------+
|                         VIEW (View)                         |
|         - SwiftUI Desktop-First Responsive Components       |
|         - Reads ViewModel state, routes user intent         |
+------------------------------+------------------------------+
                               | (Reads / Observes)
                               v
+-------------------------------------------------------------+
|                     VIEWMODEL (ViewModel)                   |
|         - @MainActor & @Observable State Containers          |
|         - Translates backend logic into display structures  |
+------------------------------+------------------------------+
                               | (Triggers operations)
                               v
+-------------------------------------------------------------+
|                     BACKEND & SERVICES                      |
|         - Actors (e.g., Network, Git, LLM Runners)          |
|         - No knowledge of UI layouts or View State          |
+------------------------------+------------------------------+
                               | (Operates on)
                               v
+-------------------------------------------------------------+
|                         CORE LAYER                          |
|         - Immutable Domain Models, Protocols & Enums        |
|         - Zero external dependencies (Foundation only)      |
+-------------------------------------------------------------+
```

### Design Guidelines & Concurrency Rules

1. **Strict Swift 6 Concurrency & Actor Isolation**:
   - Every file must be compiled under Swift 6 strict concurrency checks.
   - Core domain models and business structures are strictly `Sendable`.
   - Shared mutable state and hardware/disk operations live inside specialized `actor` entities or are marked `@MainActor` when tied to the user interface.
2. **Modern Observation Model (`@Observable`)**:
   - **Banned**: Combine framework primitives (`Publisher`, `@Published`, `AnyCancellable`, `.sink`), legacy `ObservableObject`, and property wrappers like `@StateObject` or `@ObservedObject`.
   - Only use Swift's native `@Observable` macro for view model data bindings.
3. **Desktop-First Layouts**:
   - Avoid centered mobile-centric containers, hardcoded frames, and manual root-level `GeometryReader` sizing. All primary layout sections utilize the custom `AdaptiveLayoutEngine` breakpoint framework.
4. **Secret Management**:
   - Credentials, private tokens, API keys, and GitHub OAuth states are saved strictly in the macOS **Keychain** using the `KeychainService`. Local defaults (`UserDefaults`), plists, or unencrypted text documents are never used for sensitive storage.
5. **No Force Unwraps**:
   - Force unwrapping with `!` is restricted. Every force-unwrap must carry an inline comment explaining why it is safe: `// SAFETY: <explanation>`.

---

## 🖥️ Key Subsystems & Features

### 1. Autonomous Agent & On-Device AI
SwiftCode includes an advanced embedded autonomous coding agent capable of diagnosing, planning, implementing, and validating system changes.
* **On-Device LLMs & MLX Integration**: SwiftCode features a fully local model runner using MLX (`MLXIntegration`) and Apple Intelligence routines, allowing offline code completions, syntax advice, and logic checks.
* **Agent Orchestrator**: The `AgentOrchestrator` implements an interactive execution loop (Audit ➔ Plan ➔ Implement ➔ Validate ➔ Report). The agent possesses a comprehensive tool system, granting it the capability to read, write, edit files, execute CLI commands, and build code packages.
* **OpenRouter & Codex Clients**: Connects to remote language models via `OpenRouterService` and `CodexService`, featuring real-time Server-Sent Events (SSE) stream decoders for ultra-low latency response streaming.

### 2. Local Simulation & Live Preview
Developers can preview Swift and SwiftUI views inside SwiftCode without launching Xcode.
* **SwiftRuntimeCompiler**: Leverages internal command-line compiler flags and dynamic loading utilities (`SwiftDynamicLoader`) to compile active workspace files.
* **LiveReloadManager**: Listens to disk-write changes via the file watcher and re-renders the views instantly in a native container (`PreviewHostView` / `LocalSimulationView`).
* **WKWebView Live Previews**: For web-based technologies (HTML, CSS, JavaScript, Markdown), a local server manages real-time updates inside a `LivePreviewView` powered by WebKit.

### 3. Git Integration & Source Control
A full-featured Git porcelain client built natively into the sidebar.
* **Local Git Service**: Invokes interactive shell pipelines safely (`GitService` / `GitPorcelainParser`) to fetch status, diffs, commits, branches, and remotes.
* **Gists Manager**: Allows users to manage Gists directly. Provides a complete UI to list, view historical revisions, construct diffs, and create new public/private Gists (`GitHubGistService`).
* **Pull Request & Issues Integrations**: Interfaces with the GitHub API to render open pull requests, issues, and workflow actions natively inside the workspace sidebar.

### 4. Professional Desktop UI Framework
The user interface is optimized for high-density professional environments on macOS. Located under `SwiftCode/UI/Styles/Styling/`, the Adaptive layout system eliminates rigid frames.

| Breakpoint Name | Width Range | Ideal For | Layout Characteristics |
| :--- | :--- | :--- | :--- |
| **Compact** | `0 - 1023px` | Side-by-side or small window | Single-column, 16pt padding, compact font scale |
| **Regular** | `1024 - 1439px` | Standard laptop screen | 2-column grid, 20pt padding, standard UI spacing |
| **Large** | `1440 - 1919px` | Studio display / Pro laptops | 3-column split view (Navigator, Editor, Inspector), 24pt padding |
| **Professional** | `1920 - 2559px` | 4K Display / Ultra-wide | 4-column layout, 32pt padding, maximized code area |
| **Ultra Wide** | `2560px+` | Wide monitors | 6-column widgets, 40pt padding, maximum layout expansion |

* **Adaptive Components**:
  * `AdaptivePage`: Automatically manages window metric calculations.
  * `AdaptiveGrid`: A multi-column flexible grid reacting to active window dimensions.
  * `AdaptiveSettingsPage`: Ensures configurations remain readable, capping width at `800pt`.
  * `AdaptiveEditorPage`: Anchors the primary 3-panel workspace IDE layout.
  * `AdaptiveSheet`: Presents professional macOS sheets starting at a standard `500x400pt` minimum.

### 5. Collaboration Hub
Provides rich team-based features to sync workspaces in real-time.
* **PeerSessionManager**: Discovers local and remote peers on the network to share active project packages, allowing users to invite team members and configure file access permissions.
* **Conflict Resolver**: When merging branches or receiving collaborative updates, a custom view (`CollaborationConflictResolverView`) handles overlapping diff hunks interactively.
* **Presence & Workspace Activity Logs**: Visually maps active collaborator cursor lines (`CollaborationFilePresenceOverlay`) and documents all repository activity inside an audit log.

### 6. Deployments & Continuous Integration
SwiftCode bridges the gap between local editing and production servers.
* **Built-in Deployments Manager**: Deploys web-based outputs directly to hosts like Netlify, Vercel, and GitHub Pages (`VercelManager`, `NetlifyManager`).
* **CI Build Pipeline**: Decodes build logs (`BuildLogDecoder`) from local simulations or GitHub Actions to surface detailed compilation logs, errors, and performance traces inside an integrated console.

### 7. Massive Dev Tools Suite
Directly accessible from the "Tools" section in the main toolbar, this suite contains **91 utility views** designed to solve everyday engineering tasks instantly:

* **Converters**: Hex-Decimal, Binary, JSON to Swift/Python/Java/Go, YAML/TOML/JSON inter-conversions, Case Converter, Text Case Swapper, HTML Entity Converter.
* **Formatters & Minifiers**: XML Formatter, HTML/CSS Minifiers, String Escaper, Text Deduplicator.
* **Generators**: UUID Generator, Cron Generator, Random String Generator, Lorem Ipsum Generator, CSS Shadow / Gradient Generators, URL Slug Generator, ASCII Art Generator.
* **Network & Calculators**: Port Scanner, Port Lookup, WHOIS lookup, Subnet Calculator, IP Address Info, Webhook Tester, APITester, Aspect Ratio Calculator, Percentage Calculator, Weight Converter, Timezone & Timestamp Converters.
* **Quick References**: Extensive Git Cheatsheet view.

---

## 📂 Directory Map

```
SwiftCode/
├── App/                       # Application entry, Scene configuration, Commands menu wiring
├── Assets.xcassets/           # Visual resources, icons, and theme configuration sets
├── Backend/                   # Core engines: Git, AI Providers, Deployments, FileSystem Watchers
├── Core/                      # Domain definitions: AI types, Project nodes, Build configurations
├── Features/                  # Advanced code intelligence, syntax parsers, index utilities
├── Frameworks/                # Specialized local libraries
│   └── Internal/              # Key managers overseeing package integrity, Plist, XML, and zip imports
├── Models/                    # Shared model wrappers (AppSettings, Project, FileNode, PackageDependency)
├── Resources/                 # Bundled files, templates, and static code assets
├── Services/                  # Singleton services managing loggers, syntax highlighters, keychain
├── Tools/                     # Developer command utilities and compiler helper scripts
├── UI/                        # Centralized Adaptive UI styling engines & breakout systems
├── ViewModels/                # Main-Actor isolated state providers for the UI layers
└── Views/                     # High-density SwiftUI Views (Editor, Git, Collaborations, Dev Tools)
```

---

## 🛠️ Manager & Service Catalog

### Internal Framework Managers (`Frameworks/Internal`)

These lightweight, single-purpose managers coordinate package structures, read/write configurations, and protect project integrity. All are built as thread-safe, `Sendable` singletons.

| Class / Manager | File Path | Responsibility |
| :--- | :--- | :--- |
| `ProjectCoordinator` | `ProjectCoordinator.swift` | Coordinates high-level initialization and state sync during project load/unload phases. |
| `ProjectIntegrityManager` | `ProjectIntegrityManager.swift` | Validates project manifest hashes and file package integrity structures to block/detect file corruption. |
| `ProjectSerializer` & `Deserializer` | `ProjectSerializer.swift`, `ProjectDeserializer.swift` | Handles binary-to-object conversions for saving/loading projects on disk safely. |
| `ProjectValidator` | `ProjectValidator.swift` | Audits folder configurations, verifying target structures conform to compiling rules before build. |
| `ProjectPackageManager` | `ProjectPackageManager.swift` | Manages project-specific dependency trees and local third-party library paths. |
| `ProjectErrorManager` | `ProjectErrorManager.swift` | Gathers compilation, structural, and runtime project errors into a central registry for display. |
| `ProjectJSONManager` | `ProjectJSONManager.swift` | Implements computed `JSONEncoder` and `JSONDecoder` streams to maintain Swift 6 concurrency safety. |
| `ProjectXMLManager` | `ProjectXMLManager.swift` | Safe XML parser mapping local property lists, project assets, and legacy layouts into models. |
| `ProjectPlistManager` | `ProjectPlistManager.swift` | Reads, modifies, and commits configuration overrides inside workspace `.plist` configuration files. |
| `ProjectHashManager` | `ProjectHashManager.swift` | Standardizes cryptographic hashing of project files for rapid comparison checks and integrity checks. |
| `ProjectFileManager` | `ProjectFileManager.swift` | Handles direct low-level file write operations, directories creation, and folder-structure checks. |
| `ProjectMetadataManager` | `ProjectMetadataManager.swift` | Preserves metadata tags, file-count statistics, modified dates, and custom workspace indicators. |
| `ProjectResourceManager` | `ProjectResourceManager.swift` | Collects, binds, and exposes bundled media files, assets, and storyboards to compilation targets. |
| `ProjectVersionManager` | `ProjectVersionManager.swift` | Tracks historical package migrations and validates target API levels for local simulations. |
| `ExportProjManager` | `ExportProjManager.swift` | Prepares, compresses, and packages local files for external distributions or network transfers. |
| `ImportProjManager` | `ImportProjManager.swift` | Orchestrates the extraction of incoming workspace archives and registers imported items to the main directory. |
| `ManifestProjManager` | `ManifestProjManager.swift` | Compiles and validates `manifest.json` profiles for target packages. |

### App Services (`Services`)

These core services manage the live infrastructure of the IDE, ranging from code analysis to network integrations.

| Service Name | File Path | Responsibility |
| :--- | :--- | :--- |
| `CodingManager` | `Core/CodingManager.swift` | Provides safe, atomic workspace file operations (`Data.write(..., options: .atomic)`) and shields against folder-traversal attacks. |
| `ToolbarActionManager` | `Core/ToolbarActionManager.swift` | Orchestrates dynamic menu commands, sidebar selections, and toolbar display modes across the workspace. |
| `GitHubService` | `Services/GitHubService.swift` | Interfaces with the GitHub REST & GraphQL APIs to coordinate repositories, branch requests, and pull request events. |
| `GitHubGistService` | `Backend/GitHub/GitHubGistService.swift` | Dedicated management interface for GitHub Gists (Revisions, diffs, creations, and lists). |
| `OpenRouterService` | `Services/OpenRouterService.swift` | Dispatches remote inference prompts to OpenRouter models, featuring an asynchronous stream decoder. |
| `KeychainService` | `Services/KeychainService.swift` | Securely manages persistent developer tokens, git credentials, and OAuth secrets in the macOS Keychain. |
| `LocalModelManager` | `Services/LocalModelManager.swift` | Controls local model setups, downloads, and monitors background download progress of CoreML/MLX models. |
| `ZipImporter` | `Services/ZipImporter.swift` | Unzips standard project templates or remote source files, inserting them into the user's workspace securely. |
| `ProjectTemplateManager` | `Services/ProjectTemplateManager.swift` | Stores and scaffolds preset workspace templates (e.g., SwiftUI Apps, SpriteKit games, Bluetooth systems). |
| `ProjectFilesExtracter` | `Services/ProjectFilesExtracter.swift` | Recursively processes folders, assembling high-density file matrices to build context arrays for LLM prompts. |
| `ProjectBuilderManager` | `Services/ProjectBuilderManager.swift` | Interfaces with build utilities to invoke compilation pipelines and parse errors/warnings in real time. |
| `LogManager` | `Services/LogManager.swift` | Centralizes logging streams across the app, replacing `print` with OS-native `Logger` routines. |
| `SyntaxHighlighter` | `Services/SyntaxHighlighter.swift` | Implements swift token scanning to generate syntax-highlighted code blocks for the editor views. |
| `CodeFormatter` | `Services/CodeFormatter.swift` | Formats active code files automatically, cleaning indentation, bracket structures, and trailing whitespaces. |
| `CodeIndexService` | `Services/CodeIndexService.swift` | Builds rapid index maps of workspace symbols (classes, structs, protocols, functions) to power IDE navigation. |
| `FolderManager` | `Services/FolderManager.swift` | Coordinates file groupings and directory locations inside the active project navigator view. |
| `ExtensionManager` | `Services/ExtensionManager.swift` | Tracks, loads, and manages third-party extension plugins to expand IDE features. |
| `PluginManager` | `Services/PluginManager.swift` | Sandboxes and runs integrated JavaScript/Swift script plugins inside the workspace context. |
| `NotificationManager` | `Services/NotificationManager.swift` | Dispatches user-facing macOS notifications on build completions, test finishes, or network transfers. |
| `RepoPermManager` | `Services/RepoPermManager.swift` | Governs authorization and repository permissions, ensuring collaboration pipelines remain secure. |

---

## 🧑‍💻 Developer Guide: Cloning & Contributing

### Getting Started

To get started with developing or customizing SwiftCode, ensure you meet the following baseline requirements:
* **Operating System**: macOS 14.0 (Sonoma) or newer.
* **Xcode**: Xcode 15.0+ (Xcode 16 / Toolchain 26 recommended for full Swift 6 concurrency verification).
* **Git**: System Git installed (configured path can be customized in the app's Developer settings).

```bash
# 1. Clone the repository
git clone https://github.com/user/SwiftCode-Mac.git
cd SwiftCode-Mac

# 2. Open the Xcode Project
open SwiftCode.xcodeproj
```

Once Xcode compiles the scheme, the app will launch, automatically initializing and verifying the local storage structures:
1. Creates `~/Documents/Projects/` — holds active user workspace projects.
2. Creates `~/Documents/Models/` — houses local CoreML, MLX, or downloaded local AI weights.

### The Xcode Project File Integrity Protocol (`project.pbxproj`)

When writing code that adds or modifies the physical files within the SwiftCode source tree, **do not manually add references without extreme caution.** Every Swift file tracked inside `project.pbxproj` MUST contain exactly **four** coordinated entries. Failing to register any of these four causes orphaned references, target invisibility, or Xcode project file corruption.

The four required entries for a new file `MyNewComponent.swift`:
1. **`PBXFileReference`**:
   - Represents the physical file on disk.
   - Example properties: `lastKnownFileType = sourcecode.swift`, `path = MyNewComponent.swift`, `sourceTree = "<group>"`.
2. **`PBXBuildFile`**:
   - Connects the file reference above to the build target system.
   - Example property: `fileRef = <UUID_OF_FILE_REFERENCE>`.
3. **`PBXSourcesBuildPhase`**:
   - Registers the `PBXBuildFile` UUID into the target compile sequence (under the main `9BF8BFB9B87ED46BDA700029` phase).
4. **`PBXGroup`**:
   - Inserts the `PBXFileReference` UUID into the corresponding parent group child array so that the file displays correctly in the Xcode navigator.

> ⚠️ **Warning on UUID Creation**: Every newly minted UUID must be exactly **24 characters**, uppercase hexadecimal, and completely unique. Never guess or copy existing UUIDs from other parts of the project file.

---

## ❓ Frequently Asked Questions (FAQs)

#### Q: Why are Combine, `@Published`, and `DispatchQueue` banned?
**A:** SwiftCode utilizes modern **Swift 6 Strict Concurrency** principles. Combine and `DispatchQueue` often bypass compiler-level isolation verification, introducing silent data races. By using native actors, `@MainActor` isolation, and the modern `@Observable` macro, the compiler actively proves the thread safety of every state modification.

#### Q: How does the local AI offline model function?
**A:** SwiftCode utilizes custom MLX Integration packages (`MLXSwift`) optimized for Apple Silicon neural engines. Users can download quantized models directly in the app. When the network is disconnected, `OnDeviceAIManager` routes queries locally, safeguarding developer privacy.

#### Q: Is there a test target I need to run?
**A:** SwiftCode does not maintain an automated `XCTest` test target. All code validation is completed through local build simulation, strict type-checking, compiler warning audits, and visual runtime verification using our dynamic preview engines.

#### Q: How do I resolve a `cannot compile/load` error on local previews?
**A:** Ensure your workspace path does not contain illegal special characters and that your system CLI path is correctly configured in SwiftCode settings. If you use custom SPM libraries, verify they are correctly referenced in your target dependencies list.

---

*Developed natively with ❤️ for macOS.*
