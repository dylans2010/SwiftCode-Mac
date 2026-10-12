<!-- system-index-depends: FileOperations.md -->

# BUILD & TESTING — VERIFY BEFORE CLAIMING

## 1. Exit code 0 is the only success signal

A build or test run succeeded **strictly and solely when the underlying process
terminates with exit code 0**. Everything else is unverified.

- **Never report** that compilation passed, tests completed, or issues were resolved
  without physical execution evidence.
- A tool returning without error does **not** mean the engineering objective is
  accomplished. Verification means: re-read the modified files, compile with the real
  toolchain, run the test suites, and confirm zero compiler diagnostic errors.
- An annotation or analysis pass that only *marks up* problems (e.g. prepending review
  comments above error lines) is not a fix. Always follow it with real code changes
  and a rebuild.

## 2. Build after meaningful changes

- Run the authoritative build check (`project_build` / `xcodebuild` or SwiftPM) after
  code changes that alter behavior, structure, or dependencies — not after trivial
  text inspections where nothing was modified.
- Resolve package dependencies through the toolchain when the project requires it;
  do not hand-edit lockfiles or caches as a substitute.
- If a build fails (non-zero exit), inspect stderr: parse file path, line number,
  column, severity, and message. Formulate a **targeted fix**, apply it, and rebuild.
  Do not report the failure as if describing it were resolving it.

## 3. Test genuine behavior

- After a clean, green build, run the real unit and integration test suites.
- When an assertion fails, locate the failing assertion, inspect the source, fix the
  root cause, and retest. Do not suppress the failure; do not change the test to match
  a broken implementation unless the test itself is provably wrong.
- Test the real thing, never mocks presented as the product.
- Heuristic tools — lint checks, complexity scores, line-length or TODO scans,
  advisory self-review findings — are **leads, not verification**. They can point you
  at risk; they cannot certify a build.

## 4. Pre-build hygiene (fast, but not a substitute)

Before a full build, a quick sanity pass over recent changes catches low-level
anomalies cheaply: git merge conflict markers (`<<<<<<<`), missing trailing
newlines, unreadable files, stale-file mismatches. This pass is advisory —
**it never replaces the compiler.**

## 5. Re-verify after every fix

- Each change invalidates prior verification. Re-run the relevant build and tests
  after every fix; loop until exit code 0 with zero diagnostic errors.
- Do not batch "fix then trust": the fix itself must be compiled and tested before
  you claim the issue resolved.
- When an independent review gate is enabled (`code_review`), it must pass with no
  critical issues before the task is considered complete.

## 6. Toolchain limitation condition

Some environments have **no Swift toolchain** (no `xcodebuild`, no `swiftc`). When
verification cannot run where you are:

- **State it plainly.** Say exactly what was not built or tested and that the
  verification step requires Dylan's Mac.
- **Deliver the exact verification steps** he needs (build command / scheme,
  test suite, what to look for) so the handoff is one clean run.
- **Never fabricate compiler output or exit codes.** A static-only conclusion is
  honest; an invented "build passed" is not.

## 7. Recovery discipline

- When a build or test fails, analyze the diagnostic, change the approach, and retry
  only when the retry is justified by a changed strategy.
- Never repeat the identical failing build or test invocation in consecutive turns
  expecting a different result.
- When you are blocked (missing dependency, toolchain absent, access denied), name
  the blocker and what was already attempted — then stop and report rather than
  improvising around it.
