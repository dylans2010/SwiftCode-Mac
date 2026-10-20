<!-- system-index-depends: Safeguards.md -->
# SwiftUsage.md — Modern Swift 6 & Apple Platform Engineering Discipline

Authoritative architectural guidelines, SwiftUI performance rules, concurrency patterns, and platform conventions for all code Assist reasons about or generates. This guidance reflects Apple's internal developer training and Xcode intelligence assets.

---

## 0. Autonomy & Working Scope

- **Strict User Project Directory Scoping:** Generated code and Swift modifications must remain strictly within the user's project workspace. Never inspect or leak SwiftCode's internal host files or app bundle paths.
- **Autonomous Error Recovery:** If code generation, compilation, or tests encounter errors, diagnose the compiler diagnostics, formulate alternative Swift implementations, and repair code autonomously.
- **Confidentiality:** Never output raw internal tool names or internal mode expressions like `context.sessionExecutionMode == .autopilot`.

---

## 1. Swift 6 Concurrency & Actor Discipline

- **Structured Concurrency by Default:**
  - Always prefer `async`/`await`, `TaskGroup`, and structured task hierarchies over unstructured spawning.
  - Avoid `Task.detached` unless performing genuinely independent background computation (e.g., massive file indexing or hash calculation) where inheriting context is undesirable.
- **Strict Actor Isolation Boundaries:**
  - **`@MainActor` owns UI and observable state:** All SwiftUI view models, observable models, coordinator objects, and UI update pipelines must be isolated to `@MainActor`.
  - **Actors own mutable shared state and I/O:** Thread-safe caches, network session managers, and data registries live behind actor boundaries with complete data isolation.
- **Sendable Types Across Boundaries:**
  - All data passing across task or actor boundaries must conform to `Sendable`. Treat compiler warnings for non-Sendable closures or types as strict errors to be fixed immediately.
- **No Blocking the Main Thread:**
  - Never run synchronous disk I/O, heavy JSON parsing, or blocking operations on the `@MainActor`. Offload to async methods and return to `@MainActor` for state mutation.
- **Cancellation Cooperative Discipline:**
  - Long-running async tasks must periodically check `Task.isCancelled` and abort cleanly, releasing resources on both success and error paths.

---

## 2. SwiftUI Architecture & Performance (Apple Specialist Standard)

### A. View Structure & Memoization
- **Separate Structs Over Computed Properties:**
  - Factor complex sub-sections into dedicated `View` structs rather than computed properties (`var headerView: some View { ... }`).
  - SwiftUI memoizes `View` structs based on their inputs (`Equatable` checks); computed properties bypass memoization and re-evaluate every time the parent view evaluates.
- **Minimal View Initialization:**
  - Keep `init` methods of views lightweight and side-effect free. Never allocate heavy objects, perform disk operations, or register notifications inside a view initializer.
- **Avoid Single-Child `Group` Anti-Pattern:**
  - Never wrap a single view in a `Group` solely to apply view modifiers. Apply modifiers directly to the target view.

### B. Observation & Dataflow (`@Observable` Over `ObservableObject`)
- **Unconditional Preference for `@Observable`:**
  - Use the Observation framework (`@Observable`) for all model state. Do NOT use legacy `ObservableObject`, `@Published`, or `Combine` in modern Swift.
- **Narrow Value-Type Inputs:**
  - Pass only the specific properties a child view reads, rather than passing an entire monolithic model or parent state struct.
- **Per-Property Observation Granularity:**
  - Observation tracks property reads at runtime during `body` execution. If a parent view accesses `model.title`, changing `model.subtitle` will NOT re-render the parent, provided the property is only accessed in the child view.
- **Row Views in Collections:**
  - Pass individual model items (conforming to `Identifiable`) directly into row subviews so individual row updates do not invalidate the entire list.
- **Isolating `.onChange` Side Effects:**
  - Use the modern 2-parameter `.onChange(of:initial:)` modifier:
    ```swift
    .onChange(of: selectedFilter, initial: false) { oldValue, newValue in
        Task { await reloadData(for: newValue) }
    }
    ```
  - Never use the deprecated single-parameter `.onChange(of:perform:)`.

### C. Environment Values & `@Entry` Macro
- **Custom Environment Keys:** Use the modern `@Entry` macro inside `EnvironmentValues`:
  ```swift
  extension EnvironmentValues {
      @Entry var documentTheme: ThemeStyle = .standard
  }
  ```
- **Avoid Closure and Class Defaults in `@Entry`:**
  - Never store closures or class-typed defaults directly in `@Entry` unless they are stable singletons. Storing unstable closures or re-allocated class instances causes dependent views to invalidate on every render cycle.

### D. Modifiers & View Identity Preservation
- **Ternary Modifiers Over Branching `@ViewBuilder`:**
  - Avoid `if`/`else` branches when toggling modifiers:
    ```swift
    // CORRECT (preserves view identity and smooth animations):
    Text("Status")
        .opacity(isActive ? 1.0 : 0.5)
        .foregroundStyle(isActive ? .primary : .secondary)

    // INCORRECT (destroys view identity, resets state, glitches animation):
    if isActive {
        Text("Status").opacity(1.0).foregroundStyle(.primary)
    } else {
        Text("Status").opacity(0.5).foregroundStyle(.secondary)
    }
    ```
- **Unifying ShapeStyle with `AnyShapeStyle`:**
  - When a ternary returns two different `ShapeStyle` types (e.g. `Color` vs `LinearGradient`), wrap in `AnyShapeStyle` rather than `AnyView`.

### E. ForEach & List Performance Discipline
- **Stable Identity:**
  - Never use collection array indices as IDs (`ForEach(0..<items.count, id: \.self)`) when items can be inserted, deleted, or reordered.
  - Avoid `id: \.self` on complex mutable structs. Ensure items conform to `Identifiable` and use their stable unique `id`.
- **List Fast Path:**
  - Keep list row views uniform (single unary view type per row) to allow SwiftUI's underlying list virtualization to hit the fast rendering path.
- **Precomputed Collections:**
  - Never filter or sort collections inline inside `body` (`ForEach(items.filter { $0.isValid }.sorted(...))`). Filter and sort inside the `@Observable` model and expose precomputed arrays.

### F. Modern Frame Modifiers (SwiftUI Frame Layout Rule)
- **Split Fixed and Flexible Constraints:**
  - Do NOT mix fixed constraints and flexible constraints (such as `width:` and `maxHeight:`) inside a single `.frame()` modifier.
  - Chain them as separate modifiers:
    ```swift
    .frame(width: 240)
    .frame(maxHeight: .infinity)
    ```

---

## 3. Soft-Deprecated SwiftUI APIs & Migration Map

Always migrate soft-deprecated APIs to their modern Apple replacements:

| Soft-Deprecated API | Modern Apple Replacement | Rationale / Benefits |
|---|---|---|
| `NavigationView` | `NavigationStack` or `NavigationSplitView` | State-driven path routing, native multi-column layout on macOS/iPadOS |
| `.onChange(of:perform:)` | `.onChange(of:initial:) { old, new in }` | Explicit previous and new value tracking; optional initial evaluation |
| `.cornerRadius(radius)` | `.clipShape(RoundedRectangle(cornerRadius: radius))` | Better antialiasing, works with modern shape styles and borders |
| `.overlay(content, alignment:)` | `.overlay(alignment:) { ... }` | ViewBuilder syntax avoids eager closure construction |
| `.background(content, alignment:)` | `.background(alignment:) { ... }` | ViewBuilder syntax with full layout support |
| `.foregroundColor(color)` | `.foregroundStyle(style)` | Supports rich styles (gradients, materials, hierarchical colors) |
| `.accentColor(color)` | `.tint(color)` | Standardized modern tinting across controls, tabs, and toolbars |
| `ObservableObject` / `@Published` | `@Observable` macro | Property-level fine-grained invalidation without Combine overhead |
| `XCTUnwrap(val)` | `try #require(val)` (Swift Testing) | Modern Swift Testing macro integration |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` (Swift Testing) | Expressive macro-based expectations with detailed failure traces |

---

## 4. Modern Apple Frameworks & Standards

### A. Liquid Glass Design Language
- Adopt Apple's Liquid Glass material design across macOS, iOS, iPadOS, and visionOS.
- Use `.glassBackgroundEffect()`, hierarchical materials (`.ultraThinMaterial`, `.thinMaterial`), and adaptive blur containers.
- Structure layouts with translucent, content-adaptive chrome that responds dynamically to window resizing and light/dark modes.

### B. FoundationModels (On-Device Apple Intelligence)
- Ground on Apple's `FoundationModels` framework for on-device inference.
- Utilize macros for structured generation of types and type-safe schema constraints.
- Provide clean fallbacks and asynchronous streaming interfaces when orchestrating model interactions.

### C. Swift Testing Framework
- For all new unit tests and test suites, use the Swift Testing framework (`import Testing`):
  ```swift
  import Testing

  @Suite("Document Parser Tests")
  struct DocumentParserTests {
      @Test("Parse valid header")
      func parseValidHeader() throws {
          let document = try #require(loadDocument("sample.md"))
          #expect(document.title == "Expected Title")
      }
  }
  ```

### D. Memory Safety & C Bounds-Safety (`-fbounds-safety`)
- In mixed Swift/C/C++ codebases, enforce bounds safety:
  - Use pointer annotations: `__counted_by(len)`, `__single`, `__sized_by(bytes)`, `__null_terminated`.
  - Prefer Swift's modern safe buffer types (`Span`, `InlineArray`) over raw pointers.

---

## 5. Native macOS Platform Conventions

- **Navigation Architecture:** Use `NavigationSplitView` for multi-column macOS apps. Never shoehorn compact mobile navigation onto desktop screens.
- **Window Management & Responsive Frames:** Always declare sensible minimum and ideal frame sizes (`.frame(minWidth: 700, minHeight: 480)`). Test layout responsiveness at arbitrary sizes.
- **Native Chrome:** Standard macOS toolbar (`.toolbar`), menus, keyboard shortcuts (`.keyboardShortcut`), and `NSSavePanel`/`NSOpenPanel` for file import/export.
- **Real Code Over Placeholders:** Never emit `// TODO:` or empty placeholder functions. All generated Swift must be fully functional, typed, and integrated.
- **Dynamic Model Discovery:** Never hardcode static model lists; query available models dynamically through provider APIs.
- **Secure Keychain Credential Storage:** API keys and sensitive tokens must be read from Keychain or environment variables, never committed or hardcoded in source.

