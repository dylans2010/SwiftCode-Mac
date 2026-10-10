# AGENT CONTEXT & WORKSPACE PERSISTENCE

This asset defines workspace context persistence, symbol relationship graphs, semantic code search, and runtime environment diagnostics.

---

#### `context_persistence_store`
**Capability:** Workspace Context · **Risk:** safeMutation  
**When to use:** Lightweight key-value context persistence across IDE sessions (such as active task plans, checkpoint summaries, and session flags).  
**When NOT to use:** For large binary payloads, source code buffers, or disk files that belong directly in the project tree.  
**Parameters:**  
- `key` (string, required) — context identifier key.  
- `action` (string, optional, default `"get"`) — `"set"`, `"get"`, or `"delete"`.  
- `value` (string, required when `action` is `"set"`) — value to associate with key.  
**Returns:** Current value for `get`, confirmation for `set` or `delete`.  
**Notes:** Persisted to disk as JSON at `<workspaceRoot>/.assist_context_store.json`.

---

#### `source_graph_builder`
**Capability:** Repository Discovery · **Risk:** safeRead  
**When to use:** Constructing a complete symbol, class, actor, and import relationship graph across Swift source files in the workspace.  
**When NOT to use:** When searching for a single known symbol name (use `search_symbol`); for literal text matches (use `search_text`).  
**Parameters:**  
- `path` (string, optional) — scope directory; defaults to workspace root.  
**Returns:** `file_count`, `node_count`, `relationship_count`, `imports`, `relationships` (capped at 2000).  
**Notes:** Useful for mapping architectural layers and planning large-scale refactors before making changes.

---

#### `semantic_query_engine`
**Capability:** Repository Discovery · **Risk:** safeRead  
**When to use:** Concept-level architectural code search ("find the networking service", "find SwiftUI views", "locate caching actors").  
**When NOT to use:** When you know the exact identifier (use `search_symbol`) or exact text string (use `search_text`).  
**Parameters:**  
- `query` (string, required) — concept or keyword. Common shortcuts: `view`, `model`, `service`, `actor` expand to idiomatic Swift patterns.  
- `path` (string, optional) — scope directory.  
**Returns:** `matches` formatted as `file::line` with context snippets (capped at 1500).

---

#### `env_capture_logs`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** Pulling recent log entries from the environment snapshot history, optionally correlated with a context key.  
**When NOT to use:** When inspecting a specific physical crash log on disk (use `runtime_diagnostics_engine`).  
**Parameters:**  
- `memoryKey` (string, optional) — optional context key to correlate with logs.  
**Returns:** `logs` (up to 10 snapshot lines) plus optional context preview.

---

#### `env_info`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** Retrieving runtime environment facts (operating system version, Swift compiler version, CPU cores, physical memory, workspace root).  
**When NOT to use:** Repeatedly in the same session — environment facts do not change during an IDE execution turn.  
**Parameters:** None.  
**Returns:** `os`, `locale`, `timezone`, `cpu_count`, `physical_memory_bytes`, `workspace_root`.

---

#### `runtime_diagnostics_engine`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** Analyzing an application or crash log file for exceptions, anomalies, and thread crashes.  
**When NOT to use:** For general compilation errors from `xcodebuild` (use `project_build` or `compiler_diagnostics_engine`).  
**Parameters:**  
- `logPath` (string, required) — workspace-relative path to the log file.  
**Returns:** `crash_count`, `thread_anomaly_count`, `suggestions`, `crashes`.

---

## Operational Context Management Discipline

1. **Grounded Context Assembly**: Before modifying multi-file architectures, construct the dependency graph via `source_graph_builder` to prevent breaking downstream callers.
2. **Context Window Hygiene**: Avoid stuffing raw file buffers into prompt trajectories when a targeted query via `semantic_query_engine` or `search_symbol` suffices.
3. **Session Persistence**: Record durable task states and multi-turn decisions in `context_persistence_store` rather than relying on ephemeral LLM memory.
4. **Environment Awareness**: Query `env_info` whenever diagnosing platform-specific compilation flags, Apple Silicon vs Intel compatibility, or Xcode toolchain paths.
