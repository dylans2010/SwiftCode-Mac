# AGENT MEMORY & CONTEXT PERSISTENCE

This asset defines durable memory storage, session context snapshots, dependency graphs, and environment diagnostics.

---

#### `mem_store`
**Capability:** Agent Memory · **Risk:** safeMutation  
**When to use:** Persisting durable facts, design decisions, identifiers, or project state across conversation turns.  
**Parameters:**  
- `key` (string, required) — unique memory identifier.  
- `value` (string, required) — fact or data to store.  
**Notes:** Overwrites any existing entry for the specified key.

---

#### `mem_retrieve`
**Capability:** Agent Memory · **Risk:** safeRead  
**When to use:** Reading back a previously stored fact instead of recomputing, searching the disk, or asking the user again.  
**Parameters:**  
- `key` (string, required) — identifier of the fact to retrieve.  
**Returns:** `value` associated with the key.  
**Errors:** Key not found — do not retry with the same key; the fact was never stored.

---

#### `mem_clear`
**Capability:** Agent Memory · **Risk:** potentiallyDestructive  
**When to use:** ONLY on explicit user instruction to wipe session memory.  
**When NOT to use:** As general cleanup, as a reset mechanism, or speculatively.  
**Parameters:** None.  
**Notes:** Irreversibly deletes ALL stored memory entries in the graph. Not recoverable.

---

#### `mem_context_snapshot`
**Capability:** Agent Memory · **Risk:** safeMutation  
**When to use:** Capturing current environment state, open buffers, and editor context for future reference or session resumption.  
**Parameters:** None.  
**Returns:** `snapshot_key` (UUID string) and `latest_snapshot`.  
**Notes:** Each call stores a new payload.

---

#### `context_persistence_store`
**Capability:** Agent Memory · **Risk:** safeMutation  
**When to use:** Lightweight key-value context persistence across IDE sessions (lighter than the full memory graph).  
**Parameters:**  
- `key` (string, required) — context key.  
- `action` (string, optional, default `"get"`) — `"set"`, `"get"`, or `"delete"`.  
- `value` (string, required when `action` is `"set"`) — value to associate with key.  
**Notes:** Persisted to disk as JSON at `<workspaceRoot>/.assist_context_store.json`.

---

#### `source_graph_builder`
**Capability:** Repository Discovery · **Risk:** safeRead  
**When to use:** Constructing a complete symbol, class, and import relationship graph across Swift source files in the workspace.  
**Parameters:**  
- `path` (string, optional) — scope directory; defaults to workspace root.  
**Returns:** `file_count`, `node_count`, `relationship_count`, `imports`, `relationships` (capped at 2000).

---

#### `semantic_query_engine`
**Capability:** Repository Discovery · **Risk:** safeRead  
**When to use:** Concept-level architectural code search ("find the networking service", "find SwiftUI views", "locate caching actors").  
**Parameters:**  
- `query` (string, required) — concept or keyword. Common shortcuts: `view`, `model`, `service` expand to idiomatic patterns.  
- `path` (string, optional) — scope directory.  
**Returns:** `matches` formatted as `file::line` with context snippets (capped at 1500).

---

#### `env_capture_logs`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** Pulling recent log entries from the environment snapshot history, optionally merged with memory context.  
**Parameters:**  
- `memoryKey` (string, optional) — optional memory key to correlate with logs.  
**Returns:** `logs` (up to 10 snapshot lines) plus optional memory preview.

---

#### `env_info`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** Retrieving runtime environment facts (operating system version, Swift compiler version, CPU cores, physical memory, workspace root).  
**Parameters:** None.  
**Returns:** `os`, `locale`, `timezone`, `cpu_count`, `physical_memory_bytes`, `workspace_root`.

---

#### `runtime_diagnostics_engine`
**Capability:** Diagnostics & Profiling · **Risk:** safeRead  
**When to use:** Analyzing an application or crash log file for exceptions, anomalies, and thread crashes.  
**Parameters:**  
- `logPath` (string, required) — workspace-relative path to the log file.  
**Returns:** `crash_count`, `thread_anomaly_count`, `suggestions`, `crashes`.
