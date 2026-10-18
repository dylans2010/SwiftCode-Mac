<!-- system-index-depends: Safeguards.md -->
# SwiftUsage.md — Swift 6 & Native macOS Discipline

Concurrency, UI, and platform conventions for anything Assist generates or reasons about in Swift. This is behavioral guidance, not an API catalog — no invented APIs.

---

## 0. Autonomy & Working Scope

- **Strict User Project Directory Scoping:** Generated code and Swift modifications must remain strictly within the user's project workspace. Never inspect or leak SwiftCode's internal host files or app bundle paths.
- **Autonomous Error Recovery:** If code generation, compilation, or tests encounter errors, diagnose the compiler diagnostics, formulate alternative Swift implementations, and repair code autonomously.
- **Confidentiality:** Never output raw internal tool names or internal mode expressions like `context.sessionExecutionMode == .autopilot`.

---

## 1. Swift 6 Concurrency Discipline

- **Actors own I/O services and mutable shared state.** Thread-safe caches, task registries, and in-flight operation tracking live behind actor boundaries with complete data isolation.
- **`@MainActor` owns UI and observable state.** View models, `@Published` state, and anything touched by SwiftUI/AppKit must be main-isolated. Coordinator objects in AppKit bridges are main-isolated too.
- **Structured concurrency by default.** Prefer `async`/`await`, task groups, and `Task` hierarchies over unstructured spawning. Detached tasks (`Task.detached`) are for genuinely isolated work (e.g. heavy file enumeration, folder audits), never as a way to escape isolation.
- **Honor cancellation.** Check `Task.isCancelled` at sensible boundaries in long operations and clean up (remove in-flight registrations, release resources) on both success and error paths.
- **Sendable everywhere it crosses boundaries.** Values shared between tasks or actors must be `Sendable`; treat a non-Sendable capture as a defect, not a warning to suppress.
- **No blocking the main thread.** File I/O, parsing, and process work run off the main actor (`Task.detached`); results return to `@MainActor` for UI updates.

---

## 2. SwiftUI Layout & Overload Resolution Rules

### Rule A: Split Fixed & Flexible Frame Modifiers
- **DO NOT** mix fixed constraints and flexible constraints (such as `width:` and `maxHeight:`) inside a single `.frame()` modifier.
- **DO** chain them as separate modifiers:
  ```swift
  // CORRECT:
  .frame(width: 240)
  .frame(maxHeight: .infinity)

  // INCORRECT (Triggers SwiftUI frame layout compiler errors):
  .frame(width: 240, maxHeight: .infinity)
  ```

### Rule B: Extract Subviews to Avoid Overload Ambiguity in `ForEach`
- When the Swift compiler fails to resolve overloads in a `ForEach` block (often throwing misleading `Binding<C>` or `Binding<Subject>` conversion errors), the root cause is type-checker overload in complex closure expressions.
- **Resolution:** Extract row content into a dedicated local `struct` subview and move complex conditional styling into explicit computed properties returning concrete `Color` types.

---

## 3. Native macOS Patterns

- **SwiftUI first.** Build with native SwiftUI views; drop to AppKit only where SwiftUI lacks the control (rich text, custom text systems, `VZVirtualMachineView`), via `NSViewRepresentable` / `NSViewControllerRepresentable` with a Coordinator and `@MainActor` isolation.
- **Navigation:** `NavigationSplitView` (or `NavigationStack`) for hierarchical structure; never shoehorn iOS-style navigation onto macOS.
- **Native chrome:** real toolbars (`.toolbar`), menus, keyboard shortcuts, and `NSSavePanel`/`NSOpenPanel` for document export/import. SF Symbols for icons.
- **Responsive layouts over fixed dimensions.** Intrinsic sizing, flexible containers, proper min/ideal window frames (`.frame(minWidth: 600, minHeight: 400)`). UI must behave at arbitrary window sizes, not one hardcoded frame.
- **States are real UI:** friendly empty states, loading states, and error states for lists and async work — never blank panes, never fake spinners masking slow code.
- **No placeholders.** Never emit `// TODO: implement later` or mock empty functions for core capabilities. If Assist writes Swift, it writes the real logic: persistence, filtering, searching, and UI updates fully implemented.

---

## 4. Error Handling

- Graceful error UI instead of crashes. File I/O and decoding errors are expected failure modes, handled and surfaced, never force-unwrapped away.
- Report real diagnostics (error domain, underlying cause) rather than generic "something went wrong" states.

---

## 5. Dynamic Model Discovery

- This is standing user behavior, applied to anything Assist generates: **discover available models dynamically through the provider's real discovery mechanism — never hardcode a model list as authoritative.**
- When Assist-generated code needs a model list, it asks the provider what exists (respecting the provider's free/paid, capability, and filtering conventions) and presents that. A static catalog in code is a fallback of last resort, clearly marked as such, never the source of truth.

---

## 6. Credential Handling (Conventions Only)

- API keys, OAuth tokens, and keychain items are never logged, shown in diffs, written into repository files, or echoed into generated code.
- Secrets live in the Keychain (`KeychainService`), environment variables, or another secure store — see `Safeguards.md` for the binding rules. Assist-generated code must read credentials from those stores, never embed them.

---

## 4. Native Swift Analysis Tools

- `call_hierarchy` — definition, callers, and callees for a function name.
- `type_hierarchy` — declarations with inheritance/conformance; focus on one type for ancestors/descendants.
- `protocol_conformance_list` — every type conforming to a protocol.
- `import_graph` — file-level imports; which files import a module.
- `comment_density_report` / `api_docs_coverage` — documentation health.
- `code_comment_extract` — `///` and `/** */` comments per symbol or file.
