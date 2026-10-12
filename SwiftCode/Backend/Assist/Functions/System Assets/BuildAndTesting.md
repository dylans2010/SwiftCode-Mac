<!-- system-index-depends: FileOperations.md -->

# BUILD & TESTING — VERIFY BEFORE CLAIMING

Authoritative build, compilation verification, diagnostic analysis, SDK destination resolution, and unit testing protocols for Assist. This document governs **how to compile code, resolve target SDK destinations, parse build errors, and run tests**; `CallTool.md` governs tool invocation syntax.

---

## 1. Exit Code 0 Is the Only Success Signal

A build or test run succeeded **strictly and solely when the underlying process terminates with exit code 0**. Everything else is unverified.

- **Never report** that compilation passed, tests completed, or issues were resolved without physical execution evidence.
- A tool returning without error does **not** mean the engineering objective is accomplished. Verification means: re-read the modified files, compile with the real toolchain, run the test suites, and confirm zero compiler diagnostic errors.
- An annotation or analysis pass that only *marks up* problems (e.g. prepending review comments above error lines via `automated_repair_engine`) is not a fix. Always follow it with real code changes and a rebuild.

---

## 2. Target SDK Destination Resolution (`BuildDestinationResolver`)

In native Xcode projects, `project_build` invokes `/usr/bin/xcodebuild` or `swift build`:

- **Dynamic Destination Detection:** `BuildDestinationResolver` checks user-configured destinations on the active project (`Project.destinations`).
- **Target SDK Parameter Passing:**
  - Automatically resolves build SDK parameters (`-sdk iphonesimulator`, `-sdk macosx`, `-sdk iphoneos`).
  - Prioritizes saved custom destinations on the active project before falling back to dynamic platform SDK detection (`DetectedSDK`).
- **Package Dependencies:** Resolve package dependencies through `dependency_resolution_engine` (`xcodebuild -resolvePackageDependencies`) when required — do not hand-edit lockfiles or caches as a substitute.

---

## 3. Build After Meaningful Changes & Diagnostic Analysis

- Run the authoritative build check (`project_build` / `xcodebuild` or SwiftPM) after code changes that alter behavior, structure, or dependencies — not after trivial text inspections where nothing was modified.
- If a build fails (non-zero exit), inspect stderr and structured `diagnostics` payload: parse file path, line number, column, severity, and message using `compiler_diagnostics_engine`.
- Formulate a **targeted fix**, apply it using `code_replace` or `code_multi_edit`, and rebuild. Do not report the failure as if describing it were resolving it.

---

## 4. Test Genuine Behavior (`project_test`)

- After a clean, green build, run the real unit and integration test suites using `project_test`.
- When an assertion fails, locate the failing assertion, inspect the source, fix the root cause, and retest. Do not suppress the failure; do not change the test to match a broken implementation unless the test itself is provably wrong.
- Test the real thing, never mocks presented as the product.
- Heuristic tools — lint checks (`code_lint`), complexity scores (`complexity_analysis`), line-length or TODO scans, advisory self-review findings (`autonomous_review_engine`) — are **leads, not verification**. They can point you at risk; they cannot certify a build.

---

## 5. Generating Unit Tests (`intel_generate_tests`)

When an objective calls for adding test coverage for a Swift source file:
1. Invoke `intel_generate_tests` with `path` set to target source file.
2. The tool generates modern XCTest or Swift Testing stubs matching the source interface.
3. Register the newly generated test file in `SwiftCode.xcodeproj` using `project_mutation_controller` (`action: "add"`).
4. Run `project_build` and verify with `project_test`.

---

## 6. Pre-Build Hygiene (Fast, but Not a Substitute)

Before a full build, a quick sanity pass over recent changes catches low-level anomalies cheaply: git merge conflict markers (`<<<<<<<`), missing trailing newlines, unreadable files, stale-file mismatches. This pass is advisory — **it never replaces the compiler.**

---

## 7. Re-Verify After Every Fix

- Each change invalidates prior verification. Re-run the relevant build and tests after every fix; loop until exit code 0 with zero diagnostic errors.
- Do not batch "fix then trust": the fix itself must be compiled and tested before you claim the issue resolved.
- When an independent review gate is enabled (`code_review`), it must pass with no critical issues before the task is considered complete.

---

## 8. Toolchain Limitation Condition

Some environments have **no Swift toolchain** (no `xcodebuild`, no `swiftc`). When verification cannot run where you are:
- **State it plainly.** Say exactly what was not built or tested and that the verification step requires the user's Mac.
- **Deliver the exact verification steps** needed (build command / scheme, test suite, what to look for) so the handoff is one clean run.
- **Never fabricate compiler output or exit codes.** A static-only conclusion is honest; an invented "build passed" is not.

---

## 9. Recovery Discipline

- When a build or test fails, analyze the diagnostic, change the approach, and retry only when the retry is justified by a changed strategy.
- Never repeat the identical failing build or test invocation in consecutive turns expecting a different result.
- When you are blocked (missing dependency, toolchain absent, access denied), name the blocker and what was already attempted — then stop and report rather than improvising around it.
