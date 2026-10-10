# AGENT MEMORY & USER FACTS SYSTEM

> **Asset**: `Memory.md`  
> **Scope**: User Memory, Fact Persistence, and Preferences  
> **Persistence Target**: `UserMemory.md`

This asset defines durable user memory storage, user preference tracking, and memory management rules.

---

### Operating Guardrails & Directives
- **Memory Toggle Enforcement**: When the Memory module is toggled OFF by the user, Assist must NEVER capture or alter memory, and must refuse memory operations with `"User has Memory module OFF."`
- **Integrity & Grounding**: Record genuine user facts, project conventions, and verified preferences. Never hallucinate facts or store speculative assumptions.

---

#### `capture_memory`
**Capability:** Agent Memory · **Risk:** safeMutation  
**When to use:** Storing important facts, architectural preferences, user background, or personal workflow rules into `UserMemory.md`.  
**When NOT to use:** Storing temporary scratch notes, transient build states, or when user has Memory module disabled.  
**Parameters:**  
- `memory` (string, required) — the important fact, user preference, workflow pattern, or detail to remember.  
- `category` (string, optional) — category to classify this memory (e.g. 'User Preferences & Profile', 'Project Context', 'Learned Patterns & Directives').  
**Returns:** Success confirmation and updated memory entry.  
**Errors:** Memory module disabled (`"User has Memory module OFF."`), invalid or empty memory parameter.

---

#### `retrieve_memory`
**Capability:** Agent Memory · **Risk:** safeRead  
**When to use:** Reading back user facts, user preferences, past project decisions, or custom rules from `UserMemory.md` instead of re-asking the user.  
**When NOT to use:** Querying code symbol definitions (use `search_symbol` or `search_text`).  
**Parameters:**  
- `query` (string, optional) — search keyword or phrase to filter specific memory entries. If omitted, returns all user memory.  
**Returns:** Stored memory entries matching the query, or full user memory text.  
**Errors:** Memory module disabled (`"User has Memory module OFF."`).

---

#### `manage_memory`
**Capability:** Agent Memory · **Risk:** safeMutation  
**When to use:** Updating, modifying, deleting obsolete memory, or saving new details in `UserMemory.md`.  
**When NOT to use:** Wiping memory speculatively without user direction.  
**Parameters:**  
- `modifySaved` (string, optional) — modifies an already saved entry. Can be 'Old content -> New content' or target text to update.  
- `deleteContext` (string, optional) — deletes a piece of memory matching this context or text.  
- `saveToMemory` (string, optional) — saves new details to the memory system.  
**Notes:** Deletions and modifications are persistent in `UserMemory.md`.

---

#### `mem_store`
**Capability:** Agent Memory · **Risk:** safeMutation  
**When to use:** Legacy compatibility alias for persisting durable facts across conversation turns.  
**Parameters:**  
- `key` (string, required) — unique memory identifier.  
- `value` (string, required) — fact or data to store.  
**Notes:** Overwrites any existing entry for the specified key.

---

#### `mem_retrieve`
**Capability:** Agent Memory · **Risk:** safeRead  
**When to use:** Legacy compatibility alias for reading back a previously stored fact.  
**Parameters:**  
- `key` (string, required) — identifier of the fact to retrieve.  
**Returns:** `value` associated with the key.  
**Errors:** Key not found — do not retry with the same key.

---

#### `mem_clear`
**Capability:** Agent Memory · **Risk:** potentiallyDestructive  
**When to use:** ONLY on explicit user instruction to wipe session memory.  
**When NOT to use:** As general cleanup or speculatively.  
**Parameters:** None.  
**Notes:** Irreversibly deletes stored memory entries in the graph.

---

#### `mem_context_snapshot`
**Capability:** Agent Memory · **Risk:** safeMutation  
**When to use:** Capturing current environment state and open buffers for future reference or session resumption.  
**Parameters:** None.  
**Returns:** `snapshot_key` (UUID string) and `latest_snapshot`.
