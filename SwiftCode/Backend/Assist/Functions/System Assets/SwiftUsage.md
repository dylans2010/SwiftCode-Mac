# SwiftUsage.md — Swift 6 & Native macOS Discipline

<!-- system-index-depends: Safeguards.md -->

Concurrency, UI, and platform conventions for anything Assist generates or reasons
about in Swift. This is behavioral guidance, not an API catalog — no invented APIs.

---

## 1. Swift 6 Concurrency Discipline

- **Actors own I/O services and mutable shared state.** Thread-safe caches, task
  registries, and in-flight operation tracking live behind actor boundaries with
  complete data isolation.
- **`@MainActor` owns UI and observable state.** View models, `@Published` state, and
  anything touched by SwiftUI/AppKit must be main-isolated. Coordinator objects in
  AppKit bridges are main-isolated too.
- **Structured concurrency by default.** Prefer `async`/`await`, task groups, and
  `Task` hierarchies over unstructured spawning. Detached tasks are for genuinely
  isolated work (e.g. heavy file enumeration), never as a way to escape isolation.
- **Honor cancellation.** Check `Task.isCancelled` at sensible boundaries in long
  operations and clean up (remove in-flight registrations, release resources) on both
  success and error paths.
- **Sendable everywhere it crosses boundaries.** Values shared between tasks or actors
  must be `Sendable`; treat a non-Sendable capture as a defect, not a warning to
  suppress.
- **No blocking the main thread.** File I/O, parsing, and process work run off the
  main actor; results return to `@MainActor` for UI updates.

## 2. Native macOS Patterns

- **SwiftUI first.** Build with native SwiftUI views; drop to AppKit only where SwiftUI
  lacks the control (rich text, custom text systems), via `NSViewRepresentable` /
  `NSViewControllerRepresentable` with a Coordinator and `@MainActor` isolation.
- **Navigation:** `NavigationSplitView` (or `NavigationStack`) for hierarchical
  structure; never shoehorn iOS-style navigation onto macOS.
- **Native chrome:** real toolbars (`.toolbar`), menus, keyboard shortcuts, and
  `NSSavePanel`/`NSOpenPanel` for document export/import. SF Symbols for icons.
- **Responsive layouts over fixed dimensions.** Intrinsic sizing, flexible containers,
  proper min/ideal window frames. UI must behave at arbitrary window sizes, not one
  hardcoded frame.
- **States are real UI:** friendly empty states, loading states, and error states for
  lists and async work — never blank panes, never fake spinners masking slow code.
- **No placeholders.** Never emit `// TODO: implement later` or mock empty functions
  for core capabilities. If Assist writes Swift, it writes the real logic: persistence,
  filtering, searching, and UI updates fully implemented.

## 3. Error Handling

- Graceful error UI instead of crashes. File I/O and decoding errors are expected
  failure modes, handled and surfaced, never force-unwrapped away.
- Report real diagnostics (error domain, underlying cause) rather than generic
  "something went wrong" states.

## 4. Dynamic Model Discovery

- This is standing user behavior, applied to anything Assist generates: **discover
  available models dynamically through the provider's real discovery mechanism —
  never hardcode a model list as authoritative.**
- When Assist-generated code needs a model list, it asks the provider what exists
  (respecting the provider's free/paid, capability, and filtering conventions) and
  presents that. A static catalog in code is a fallback of last resort, clearly marked
  as such, never the source of truth.

## 5. Credential Handling (Conventions Only)

- API keys, OAuth tokens, and keychain items are never logged, shown in diffs, written
  into repository files, or echoed into generated code.
- Secrets live in the Keychain, environment variables, or another secure store — see
  Safeguards.md for the binding rules. Assist-generated code must read credentials from
  those stores, never embed them.
