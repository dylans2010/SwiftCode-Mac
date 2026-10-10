# BUILD, TEST & DIAGNOSTICS VALIDATION

This asset specifies compiler execution, testing harnesses, automated code review gates, and exit code 0 enforcement.

---

## 1. Exit Code 0 & Zero Speculative Success
A build or test execution is considered successful **strictly and solely when the underlying process terminates with exit code 0**.
- **No Speculative Success**: Never report that compilation passed, tests completed, or issues were resolved without physical evidence from tool execution.
- **Diagnostics Analysis**: When a build fails (non-zero exit code), inspect stderr, analyze compiler diagnostics (file path, line number, column, severity, and error message), formulate a targeted fix, and rebuild.

---

#### `project_build`
**Capability:** Compilation & Build · **Risk:** execution  
**When to use:** Verifying compilation with the real toolchain after code changes. This is the **authoritative build check** in SwiftCode.  
**When NOT to use:** Speculatively after trivial text inspections where no code was modified.  
**Parameters:**  
- `scheme` (string, optional; default: active scheme / `"SwiftCode"`) — Xcode scheme or SPM target.  
- `configuration` (string, optional; default: `"Debug"`) — build configuration (`"Debug"`, `"Release"`).  
**Returns:** `status` (`Passed`), `duration`, `diagnostics_count`, exit code 0, and `suggestedNextActions` (`project_test`, `code_review`).  
**Errors:** Build failure returns diagnostics plus an error — fix issues and rebuild. Suggested next actions: `file_read`, `code_replace`, `project_build`.  
**Notes:** Runs real `xcodebuild` or SwiftPM toolchain; writes build artifacts; resolves dependencies.

---

#### `project_test`
**Capability:** Testing & QA · **Risk:** execution  
**When to use:** Running unit and integration test suites after achieving a clean, green build.  
**Parameters:**  
- `scheme` (string, optional) — test scheme.  
- `testPlan` (string, optional) — specific xcodebuild test plan name.  
**Returns:** Pass/fail summary with failure diagnostics, test counts, and process exit code.  
**Errors:** Test assertion failures return diagnostics — locate failing assertions, inspect source, fix, and retest.

---

#### `safe_validate_changes`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** Fast sanity pass over recent changes to detect low-level syntax anomalies before building.  
**Parameters:**  
- `path` (string, optional, default `"."`) — directory or file to validate.  
**Returns:** `issue_count` and `issues`.  
**Notes:** Checks unreadable files, git merge conflict markers (`<<<<<<<`), and missing trailing newlines. Not a substitute for a compiler build.

---

#### `compiler_diagnostics_engine`
**Capability:** Diagnostics & Profiling · **Risk:** execution  
**When to use:** Collecting structured compiler warnings and errors without executing a full build flow. macOS only.  
**Parameters:**  
- `project` (string, optional) — project path.  
- `scheme` (string, optional) — target scheme.  
**Returns:** `error_count`, `warning_count`, `errors`, `warnings` (capped at 200 lines each).  
**Notes:** Runs `xcodebuild`; a failing build does not fail the tool — parse the payload to extract line numbers and error diagnostics.

---

#### `automated_repair_engine`
**Capability:** Diagnostics & Profiling · **Risk:** safeMutation  
**When to use:** Annotating reported compiler error lines in source files for guided review.  
**Parameters:**  
- `errors` (string, required) — diagnostic lines in `path:line:...` format, typically obtained from `compiler_diagnostics_engine`.  
**Notes:** Prepends `// AssistAutoRepair: review required` above each reported error line. This is an **annotation tool only** — it does not fix bugs or rebuild. Always follow with real code fixes and `project_build`.

---

#### `dependency_resolution_engine`
**Capability:** Compilation & Build · **Risk:** execution  
**When to use:** Resolving Swift package dependencies in Xcode projects. macOS only.  
**Parameters:**  
- `packageURL` (string, required) — URL of the package repository.  
**Notes:** Runs `xcodebuild -resolvePackageDependencies` on `SwiftCode.xcodeproj`. Resolves package caches over the network.

---

#### `autonomous_review_engine`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** Heuristic self-review pass detecting force-unwraps (`!`), concurrency hazards, or excessive complexity.  
**Parameters:**  
- `path` (string, optional) — scope directory; defaults to workspace root.  
**Returns:** `finding_count`, `findings` (advisory strings, capped at 1000). Findings are advisory leads, not verified compiler errors.

---

#### `code_review`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** The independent AI code review gate before finalizing an implementation task.  
**Parameters:** None. Reads `com.swiftcode.assist.enableCodeReview` from user settings and requires `CodeReviewSystemAsset.md` in the bundle.  
**Returns:** Serialized review JSON (`status`, `summary`, `strengths`, `issues`, `recommendedFixes`, `confidence`).  
**Notes:** Uses an independent reviewer model. Must pass with confidence >= 0.85 and zero critical issues before completion.

---

#### `code_lint`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** Fast hygiene check on code files.  
**Parameters:**  
- `path` (string, optional, default `"."`) — path to lint.  
**Returns:** `issues` list or clean status. Checks line lengths over 120 chars and TODO/FIXME markers.

---

#### `complexity_analysis`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** Rough complexity evaluation of a file before refactoring.  
**Parameters:**  
- `path` (string, required) — path of the target file.  
**Returns:** `score` and `rating` (Low, Medium, High). Keyword-based heuristic.

---

#### `code_summary`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** Quick quantitative overview of a file or directory (sizes, line counts) before in-depth inspection.  
**Parameters:**  
- `path` (string, required) — path of the target file or directory.  
**Returns:** `summary` — line counts, comment counts, and file statistics.
