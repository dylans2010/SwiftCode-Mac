# SEARCH & CONTEXT DISCOVERY

This asset specifies behavioral patterns, parameter requirements, and usage guidelines for codebase search and context exploration tools.

---

#### `search_text`
**Capability:** Repository Discovery · **Risk:** safeRead  
**When to use:** Finding literal text matches across project files ("where is X referenced or called").  
**When NOT to use:** For regex patterns (use `search_regex`); for symbol declarations (use `search_symbol`).  
**Parameters:**  
- `pattern` (string, required) — literal text to locate across files; not interpreted as regex.  
**Returns:** `results` — per-file `relpath` with matching lines and line numbers.

---

#### `search_regex`
**Capability:** Repository Discovery · **Risk:** safeRead  
**When to use:** Pattern-based content searches across repository files (e.g. matching specific function signatures, annotations, or variable assignments).  
**When NOT to use:** For simple fixed substrings where `search_text` suffices.  
**Parameters:**  
- `pattern` (string, required) — regular expression syntax. Invalid regex surfaces as an error: fix the pattern syntax rather than retrying blindly.  
**Returns:** `results` — `relpath:match` lines sorted by file.

---

#### `search_symbol`
**Capability:** Repository Discovery · **Risk:** safeRead  
**When to use:** Locating Swift declarations — classes, structs, enums, protocols, functions, variables — by identifier name.  
**When NOT to use:** For arbitrary string search (use `search_text`); for semantic concept exploration (use `semantic_query_engine`).  
**Parameters:**  
- `symbol` (string, required) — symbol name matched against Swift declaration grammar.  
**Returns:** `results` — deduplicated, sorted `relpath:match` lines showing symbol declaration sites.

---

#### `dependency_graph`
**Capability:** Repository Discovery · **Risk:** safeRead  
**When to use:** Understanding module, import, and architecture relationships across Swift files in the workspace.  
**Parameters:**  
- `path` (string, optional) — directory to scan; defaults to workspace root.  
**Returns:** `node_count`, `edge_count`, `nodes`, `edges` (`src -> module`). Scans `.swift` files up to 300KB.

---

### Cloud Toolkit Search Tools Reference

#### `search_directory`
- **Capability:** Cloud Directory Grep · **Risk:** safeRead
- **Parameters:** `query` (string, required) — regex or literal text pattern to search for across repository files.
- **Usage:** Fast search across codebase in cloud workspace environments.

#### `search_web`
- **Capability:** Web Discovery · **Risk:** safeRead
- **Parameters:** `query` (string, required) — web search query.
- **Usage:** Searches online developer documentation, Apple Developer guides, open-source repositories, and technical resources.

#### `read_url_content`
- **Capability:** Web Discovery · **Risk:** safeRead
- **Parameters:** `url` (string, required) — public HTTP(S) URL to fetch.
- **Usage:** Fetches documentation, API specs, and online references for external libraries or frameworks.
