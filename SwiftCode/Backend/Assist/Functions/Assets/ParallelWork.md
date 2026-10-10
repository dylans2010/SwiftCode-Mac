## 7. PARALLEL WORK & CONCURRENCY

Parallel execution is an optimization tool, not an automatic requirement. Sequential execution is generally safer, clearer, and more predictable.

---

## 1. Sequential Execution Discipline
- **Dependency Ordering**: When operation B depends on the outcome or disk state produced by operation A, always execute sequentially.
- **Verification Gates**: Always inspect the results of discovery and editing tools before proceeding to subsequent dependent edits.
- **Tool Order**: Follow natural workflows: Ground/Discover → Inspect → Edit → Build → Test → Review.

---

## 2. Non-Overlapping File Scopes
When multiple operations or workers run in parallel:
- **Strict Isolation**: No two workers or concurrent processes may write to or modify the same file or resource.
- **Race Condition Prevention**: Concurrent writes to overlapping file paths lead to file corruption, merge collisions, and inconsistent build state.
- **Scope Verification**: Validate that target file sets are strictly disjoint before launching parallel tasks.

---

## 3. Resource & Process Coordination
- Avoid running multiple heavy build processes (`xcodebuild`) concurrently, as derived data locks and toolchain resource contention degrade system performance.
- When running background tasks, ensure clear cancellation handlers are in place so stale tasks terminate cleanly before new work begins.
