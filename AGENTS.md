# SwiftCode for Mac — AI Agent Guide & Rules (AGENTS.md)

> **File Scope:** Root of SwiftCode codebase.
> **Target Audience:** All AI Agents (especially Jules) operating on this repository.
> **Compliance:** Strict, mandatory compliance is required. Any deviation is considered an implementation failure.

---

## 1. Executive Mandates & Hard Rules

These three executive mandates supersede all other instructions and must be followed with absolute rigor.

### Rule 1: Automatic Registration of New Swift Files
If you create any new Swift file, you **MUST** automatically register it within the Xcode project structure (`project.pbxproj`) without being explicitly asked or told to do so. This is a basic yet critical rule. Leaving a file unregistered or orphaning it is a direct violation of project integrity.
To register a new file correctly, you must implement the **4-Entry Coordinated Protocol** in `SwiftCode.xcodeproj/project.pbxproj`:
1. **`PBXFileReference`**: Add a reference for the file on disk. Specify `lastKnownFileType = sourcecode.swift`, path, and `sourceTree = "<group>"`.
2. **`PBXBuildFile`**: Add a build file pointing to the `PBXFileReference` UUID.
3. **`PBXSourcesBuildPhase`**: Append the `PBXBuildFile` UUID to the target's build phase (Sources Build Phase: `9BF8BFB9B87ED46BDA700029`).
4. **`PBXGroup`**: Append the `PBXFileReference` UUID to the correct parent group children array.

#### Known UUIDs for Groups and Build Phases
Use these exact uppercase 24-character hexadecimal UUIDs when placing files into the corresponding directories:
* **Core/AI**: `DA941B6FA862048858B975DF`
* **Core/AI/Agent**: `9FAB492FE3914F789AA58201`
* **Tools/Agentic**: `D3C76C44A71C4A3EB65045B1`
* **ViewModels**: `C38806164DD566333A92A410`
* **Views**: `FE18E54E76741F54A82CD586`
* **Utilities**: `576E45E47FC5098A3A96ECB8`
* **Dashboard**: `EA26B0E5D067B5922CF6F2C8`
* **Backend/AI**: `DF6B1A5F79682983F71C7E7E`
* **Backend/Git**: `E063E218D13ACDDD0B728F8D`
* **Persistence/Templates**: `265E9A432B28B39C005F9A10`
* **Models**: `2B21AC80A9DC86CB7D9BD14F`
* **Services**: `57AFC04E569B8BDE2658ECD4`
* **GitHub**: `718173758FBD56C156A0D0F5`
* **Dev Tools**: `2B4CEE860D734A23837F5302`
* **UI/Styles/Styling**: `B0020001B0020001B0020001`
* **Sources Build Phase**: `9BF8BFB9B87ED46BDA700029`

Every UUID you generate for new items must be a unique, 24-character uppercase hexadecimal string.

### Rule 2: Absolute Autonomy & No Clarification Requests
You may **NEVER** ask the user for input, feedback, or clarification. Do not prompt, message, or use tools to ask questions. You must solve all tasks entirely autonomously.
- If a task is underspecified or ambiguous, perform a codebase audit, inspect existing patterns, and make highly professional, best-practice engineering decisions.
- Document any assumptions made, architectural directions taken, or decisions resolved in your final report.

### Rule 3: Zero Mocking / Zero Placeholders / Zero Fake Data
When creating new systems, adding new features, or modifying existing ones, you may **NEVER** write mocks, stubs, placeholders, fake data, or temporary structures.
- All code, data pipelines, integrations, and services must use **real data** and be fully end-to-end functional.
- Do not use comments like `// TODO: Implement later`, `// FIXME`, or return fake mock objects.
- If you build a service, connect it to the real underlying APIs, databases, or subsystems immediately. If a downstream module or system doesn't exist yet, build it out in a fully functional state.

---

## 2. SwiftCode Architecture Blueprint

SwiftCode is a native macOS IDE built with Swift 6 and SwiftUI. It adheres to a downward-only dependency model.

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

### Architectural Constraints
1. **Core Layer**: Contains pure domain models, protocols, and fundamental business rules. Dependencies must only be system frameworks (e.g., Foundation). No imports of Backend, ViewModel, or View layers.
2. **Backend & Services Layer**: Contains actors and manager singletons executing intensive background processes (e.g., file system I/O, LLM operations, Git commands, compilation).
3. **ViewModel Layer**: MainActor-isolated, observable types that bridge the background layers with display-ready state.
4. **View Layer**: Pure SwiftUI views that consume state from the ViewModel. Do not embed raw business or network logic directly inside views.

---

## 3. Subsystem Technical Breakdown

### 3.1 Adaptive Desktop UI System
All views must utilize the centralized adaptive layout engine located in `SwiftCode/UI/Styles/Styling/`.
- **AdaptiveBreakpoints**: Standardizes desktop responsiveness (Compact, Regular, Large, Professional, Ultra Wide).
- **AdaptiveWindowMetrics**: Supplies environment-driven sizing, padding, and spacing.
- **AdaptiveLayoutEngine**: MainActor singleton tracking window properties.
- **Adaptive Components**: Replace mobile-style and hardcoded frames with:
  * `AdaptivePage` (responsive content wrapper)
  * `AdaptiveGrid` (responsive multi-column layout)
  * `AdaptiveSettingsPage` (width-constrained centered view)
  * `AdaptiveEditorPage` (3-panel IDE layout: Sidebar, Content, Inspector)
  * `AdaptiveDashboardPage` (high-density scrollable widget panel)
  * `AdaptiveSheet` (desktop-optimized sheet)
  * `AdaptiveSplitLayout` (native NavigationSplitView integration)
- **Rules**: Never use hardcoded frame dimensions like `.frame(width: 800, height: 600)`. Use `.macDesktopOptimized()` or metrics paddings.

### 3.2 Thread-Safe File & Project Management
- **TextBufferEngine**: An actor implementing thread-safe file operations. Writes must use `.atomic` options to avoid corrupted project/file states.
- **CodingManager**: Manages atomic file manipulation, checking project-relative paths to prevent directory-traversal attacks.
- **ProjectManager**: Orchestrates project lifecycles. Offloads heavy operations (such as loading recursive file structures) to background tasks with `nonisolated` functions (`buildFileTreeInternal`). Avoid referencing the shared `ProjectManager` instance during singleton initialization.

### 3.3 Strict Swift 6 Concurrency & State
- All code must compile cleanly under Swift 6 strict concurrency rules.
- **Banned Primitives**: `Combine` (`Publisher`, `@Published`, `sink`), `DispatchQueue`, `ObservableObject`, `@StateObject`, `@ObservedObject`.
- **Permitted Primitives**: `actor`, `Task`, `async/await`, `@Observable` (with `@State` or `@Bindable`).

### 3.4 Security & Secrets
- Never store API keys, Personal Access Tokens, or passwords in plain text, `UserDefaults`, plists, or `.env` files.
- All secrets must be securely stored in the macOS Keychain using `KeychainService`.

### 3.5 Error Handling & Logging
- Use typed error enums. Swallowing errors with silent `catch {}` blocks is strictly prohibited.
- Do not use `print()` or `NSLog()`. Always use the unified `LogManager` which maps to system `Logger`.

---

## 4. Coding Standard Reference (Do's & Don'ts)

### Concurrency & State (Correct ✅)
```swift
// Modern swift State & Observation
@Observable
@MainActor
final class ProjectSettingsViewModel {
    var themeName: String = "Default"
    var isSaving = false
    private let manager: ProjectMetadataManager

    init(manager: ProjectMetadataManager) {
        self.manager = manager
    }

    func updateTheme(_ newTheme: String) async {
        isSaving = true
        defer { isSaving = false }
        // Invoke backend / service asynchronously
        await manager.saveThemePreference(newTheme)
        themeName = newTheme
    }
}
```

### Concurrency & State (Banned ❌)
```swift
// DEPRECATED: Do not use Combine / ObservableObject
final class ProjectSettingsViewModel: ObservableObject {
    @Published var themeName: String = "Default"

    func updateTheme(_ newTheme: String) {
        DispatchQueue.main.async { // BANNED: Do not use DispatchQueue
            self.themeName = newTheme
        }
    }
}
```

### Force Unwrapping (Correct ✅)
```swift
// SAFETY: Checked count above; array is guaranteed to contain at least one element.
let activeElement = elements.first!
```

### Force Unwrapping (Banned ❌)
```swift
let activeElement = elements.first! // BANNED: Missing explanatory SAFETY comment
```

### Layout Constraints (Correct ✅)
```swift
struct CustomSettingsView: View {
    var body: some View {
        AdaptiveSettingsPage {
            VStack {
                Text("Theme Configuration")
                // Uses adaptive metrics
            }
        }
    }
}
```

### Layout Constraints (Banned ❌)
```swift
struct CustomSettingsView: View {
    var body: some View {
        VStack {
            Text("Theme Configuration")
        }
        .frame(width: 800, height: 600) // BANNED: Hardcoded frame anti-pattern
    }
}
```

---

## 5. Definition of Done Checklist

Every task execution must fulfill this checklist entirely before being marked complete:

- [ ] **Auto-Registration Validation**: If new files were added, verify `project.pbxproj` has exactly 4 entries per new file, pointing to correct groups and build phases.
- [ ] **No Mocks / Placeholders**: Verify all added code is 100% complete and uses real data. No stubs, placeholders, or mocked models.
- [ ] **No Human Input**: Ensure no questions or clarification prompts were sent to the user during the entire task lifecycle.
- [ ] **Swift 6 Strict Concurrency**: Ensure zero concurrency warnings or errors are introduced. No banned Combine/DispatchQueue elements.
- [ ] **Clean Build**: Execute project validation and build to guarantee compiling source with zero new errors/warnings.
- [ ] **Detailed Final Report**: Formulate the structured summary outlining Objectives, Files Touched (labeled new/modified/deleted), Architecture Notes, Assumptions, and Build Status.
