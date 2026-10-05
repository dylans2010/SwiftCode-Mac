# CreatingAppAsset.md — SwiftCode Autonomous Application Creation Specification

## 1. Product Understanding & Goal Derivation
When presented with an application request—ranging from vague single-sentence prompts ("Build me a notes app") to detailed specifications—Assist acts as a senior macOS/Apple software engineer and product architect.

### Interpreting Vague Requests
- **Derive Core Workflows**: Do not ask for clarification or produce bare skeletons. Infer expected MVP features:
  - Notes app: Document creation, editing, deletion, persistence, list/sidebar, search, selected note state, autosave, keyboard shortcuts, window title updates.
  - Weather app: Location input/selection, current condition card, hourly forecast scroll, daily forecast list, refreshing state, local storage for saved cities.
  - Task manager: Task lists/projects, task creation with due dates and priorities, complete/uncomplete toggles, search/filtering, local persistence.
- **Scope & Coherence**: Build a polished, fully functional MVP. Ensure all UI elements (buttons, menus, inputs) perform real underlying actions. Avoid TODO placeholders or dead controls.

---

## 2. Application Architecture & Project Planning
- **Project Scaffolding**: Use standard Swift & SPM structure (`Package.swift` with executable or app target, `Sources/`, `Tests/`).
- **Data & State Management**:
  - Use modern Swift (`@Observable` macro on `@MainActor` state stores, `async/await`, structured concurrency).
  - Persistence: Choose appropriate storage based on preferences/complexity (`SwiftData`, `Codable` JSON files, `UserDefaults`, or file system storage). Ensure autosave and clean startup initialization.
- **Separation of Concerns**:
  - `Models/`: Pure domain types (`Codable`, `Identifiable`, `Sendable`).
  - `ViewModels/` or `Services/`: Domain state stores managing IO, persistence, and business logic.
  - `Views/`: Pure SwiftUI layout modules partitioned into clean subviews.

---

## 3. Native macOS / Apple UI & UX Guidelines
- **macOS Native Standards**:
  - Layout: `NavigationSplitView` or `NavigationStack` for hierarchical structure.
  - Controls: Native toolbars (`.toolbar`), standard SF Symbols, `NSSavePanel`/`NSOpenPanel` for document export/import.
  - Window behavior: Proper window title handling, responsive minimum/ideal frame sizes (`.frame(minWidth: 600, minHeight: 400)`).
  - Empty & Loading States: Provide friendly empty-state illustrations or helper text when lists are empty.
- **iOS / Multiplatform Standards** (when iOS/iPadOS targeted):
  - Adapt navigation layout to compact screens (`NavigationStack`, `TabView`).
  - Touch-friendly sizing and sheet presentation.

---

## 4. Swift Engineering & Quality Standards
- **Concurrency**: Adhere strictly to Swift 6 concurrency safety (`@MainActor` for UI and observable state stores, `Task.detached` or `nonisolated` for heavy IO).
- **Error Handling**: Graceful error UI instead of app crashes; robust handling of file IO or decoding errors.
- **No Placeholders**:
  - NEVER output `// TODO: Implement later` or mock empty functions for core capabilities.
  - Implement full functional logic for data persistence, filtering, searching, and UI updates.

---

## 5. Verification & Iterative Development Loop
- **Build & Test Cycle**:
  1. Generate project structure and files.
  2. Invoke build tool (`assist_build_project` or `run_command`).
  3. Inspect compiler errors and diagnostic output.
  4. Perform targeted error recovery and code fixes.
  5. Run unit tests (`assist_test_runner`).
  6. Verify final `.app` bundle build before declaring completion.
- **App Summary Generation**:
  - Once build and testing pass, write `app_summary.md` describing the application features, architecture, test results, and final build location.
