# TOOL SCHEMAS & PARAMETER DISCIPLINE

## 1. Source-Grounded Arguments
Every argument value must come from verified sources:
- The user's explicit reference or instruction,
- Direct repository inspection (`dir_read`, `tree_view`, `file_read`),
- A previous tool result in the session trajectory,
- The current workspace disk state.

**Never invent paths, IDs, branch names, snapshot hashes, or enum values.**

---

## 2. Path Rules & Traversal Prevention
All file paths passed to tools must be strictly workspace-relative (e.g. `Sources/App.swift`, `SwiftCode/Backend/Assist/AssistManager.swift`).

- **No Relative Traversal**: Never use `..` or relative parent references. The registry validator automatically rejects `..` in all path arguments.
- **No Absolute Paths**: Leading `/` paths (e.g. `/Users/...`) are rejected by tool validators.
- **Filesystem Sandbox**: `AssistPermissionsManager` blocks access to system-level directories at execution time:
  - `/System`
  - `/usr`
  - `/bin`, `/sbin`
  - `/etc`, `/var`
  - `/Library`
  - `/private`, `/dev`, `/tmp`

---

## 3. Parameter Validation Before Calling
Before invoking any tool, verify:
1. **Required Fields**: Ensure all required fields specified by the tool schema are non-nil and non-empty.
2. **Legal Enum Values**: Enum strings must match schema definitions exactly (e.g. `mode` for `code_insert` must be exactly `"line"`, `"before"`, or `"after"`).
3. **Real Identifiers**: IDs must originate from real preceding tool outputs:
   - Snapshot IDs from `project_snapshot` or `project_changelog`.
   - Plan IDs from `intel_plan_task`.
   - Worker names from current batch specifications in `use_workers`.
4. **Target Resource Existence**: Ensure files exist before attempting reads, appends, renames, or replaces.

---

## 4. Parameter Typing Quirks & Type Safety
Type mismatches cause immediate deterministic failures. Avoid retrying identical malformed arguments. Observe specific tool quirks:
- `use_terminal`: `modifiesRepo` is the **string** `"true"` or `"false"`, NOT a boolean.
- `use_mcp`: `arguments` is a **JSON-serialized string** (e.g. `"{}"`), NOT an object.
- `tree_view`: `maxDepth` is a decimal **string** (e.g. `"3"`), NOT an integer.
- `code_insert`: `line` is a decimal **string** (e.g. `"1"`), NOT an integer.
- `code_mutation_engine`: requires either `symbol` or `target` string argument.
- `version_control_operator`: `action` must be one of `"status"`, `"commit"`, `"branch"`, `"rollback"`, or `"diff"`.
- `code_replace`: `allowMultiple` is a boolean (default `false`).
- `file_create`: `overwrite` is a boolean (default `false`).
