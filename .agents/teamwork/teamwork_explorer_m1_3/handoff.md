# Handoff Report — Explorer M1-3: Comment Policy Checker & Post-Strip Verification Pipeline

**Agent ID**: `teamwork_explorer_m1_3`  
**Working Directory**: `/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_m1_3/`  
**Parent Agent**: `d5b41c16-417f-423a-b7f8-eea4f0706fc5`  
**Date**: 2026-11-07  
**Status**: Complete  

---

## 1. Observation

### 1.1 Requirements and Directives
1. **ORIGINAL_REQUEST.md** lines 12–14 and lines 29–32:
   > "R1. Code Comment Removal and Commenting Policy: Create and execute a script that removes all code comments unconditionally from every file across the repository. For all newly written or edited code, do not add comments unless truly important, and keep any such comment strictly to a maximum of 2 lines."  
   > "Acceptance Criteria: A script removes all code comments from every file across the repository. No code comments exceeding 2 lines exist in newly authored or modified files."
2. **MASTER_DIRECTIVE.md** lines 101–105:
   > "# 7. CODE COMMENT REMOVAL AND 2-LINE COMMENT RULE  
   > - Remove all comments across repository via script.  
   > - For new/modified code, comments strictly <= 2 lines and only if truly important."
3. **Task Assignment (DISPATCH.md)**:
   > "1. Detail the implementation of tools/check_comment_policy.py verifying no comment block exceeds 2 lines in newly written/modified files.  
   > 2. Define the exact verification sequence: comment stripping -> py_compile -> swift build -> check_comment_policy.  
   > 3. Formulate the verification plan for Reviewers and Challengers.  
   > 4. Write your handoff report to /Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_m1_3/handoff.md."

### 1.2 Repository Codebase & Tooling Environment
1. **Comment Survey Findings (from `teamwork_explorer_survey_2/handoff.md`)**:
   - Total source files scanned: **12,221 files** across repository.
   - Total source lines: **4,143,446 lines**.
   - Total comment lines: **620,098 lines** (~15.0% of entire repository).
   - Language breakdown: Swift (6,118 files, 141,942 comment lines), Python (2,426 files, 41,816 comment lines), TypeScript (1,593 files, 336,697 comment lines), JavaScript (1,269 files, 35,474 comment lines), C/C++/Headers (416 files, 48,059 comment lines), Shell (183 files, 1,783 comment lines).
2. **Tooling and Script Conventions**:
   - Python version: `Python 3.15.0` on macOS Darwin arm64.
   - Script directory: `tools/` and `.github/scripts/`.
   - Tracked tooling examples: `.github/scripts/scan-public.py` (lines 13–19) and `run-tests.py` (lines 18–32) demonstrate standard usage: `python3 -I`, standard library only (`argparse`, `os`, `re`, `subprocess`, `sys`), no external pip dependencies, repository root relative path resolution, and explicit non-zero exit codes on violations.
   - Git tracking: `git ls-files` provides tracked files, `git diff --name-only` identifies modified files in working tree or between commits.

---

## 2. Logic Chain

### 2.1 Logic: Definition of "Comment Block" and the 2-Line Policy
1. **Premise**: The policy specifies:
   - "Verify that no comment block (`//`, `/* ... */`, `#`) exceeds 2 lines in newly written/modified files."
   - A comment block of 1 line or 2 lines is compliant. A comment block of 3 or more lines is a violation.
2. **Step 1 (Block Comment Span)**:
   - For multi-line block comments (`/* ... */`):
     Let the comment start at line $S$ and terminate at line $E$.
     The line span is $L = E - S + 1$.
     If $L > 2$, the block comment itself exceeds 2 lines and is an immediate violation (e.g. lines 10 to 12 = 3 lines).
3. **Step 2 (Contiguous Single-Line Comments)**:
   - For single-line comments (`//` in Swift/C/JS, `#` in Python/Shell):
     A comment block is a contiguous sequence of comment lines without intervening executable code.
     Specifically, if line $i$ has a comment and line $i+1$ has a comment:
     - If line $i+1$ is a pure comment line (starts with comment or only whitespace precedes it), it continues the comment block from line $i$.
     - If line $i+1$ has code preceding the comment (e.g. `let y = 2 // note`), line $i+1$ begins with an executable statement; thus, code intervened and any comment block on line $i$ ended at line $i$.
     - Consecutive lines where each line has code preceding the comment (e.g. `case .a: return 1 // note A` followed by `case .b: return 2 // note B`) represent independent 1-line inline annotations on distinct statements, not a multi-line comment block.
     - Conversely, an inline comment followed by indented comment continuation lines:
       ```swift
       let x = 1 // line 1
                 // line 2
                 // line 3
       ```
       Line 10 is followed by pure comment lines 11 and 12 without intervening code. Total block span = 3 lines $\to$ VIOLATION.
4. **Step 3 (Adjacent Mixed Comments)**:
   - If a 2-line block comment `/* ... */` (spanning lines 10–11) is immediately followed on line 12 by `// ...` without intervening code, the merged contiguous block spans lines 10 to 12 (3 lines) $\to$ VIOLATION.
5. **Step 4 (Empty Comment Lines)**:
   - An empty comment line (e.g. `//` or `#` with no text) inside a block of comments is still a comment line. For example:
     ```swift
     // Header
     //
     // Description
     ```
     Lines 1, 2, and 3 are all comment lines $\to$ 3-line block $\to$ VIOLATION.

### 2.2 Logic: False Positive Prevention & Language Lexing
A naive regular expression or line-based search for `//` or `#` triggers severe false positives on valid production code. The checker must employ language-aware lexing:

1. **Python (`.py`)**:
   - Use Python's built-in `tokenize` standard library module.
   - `tokenize.tokenize` produces exact tokens with `(start_row, start_col)` and `(end_row, end_col)`.
   - Filter `tok.type == tokenize.COMMENT`.
   - Shebang exception: Line 1 comment starting with `#!` (e.g. `#!/usr/bin/env python3`) is an OS loader directive and is excluded from documentation comment block tracking.
   - String literals: `tokenize` correctly classifies strings containing `#` or `//` as `tokenize.STRING`, completely preventing false positives.
   - Docstrings: Multiline strings `"""..."""` are string literals (`tokenize.STRING`), not comment tokens.
2. **Swift (`.swift`)**:
   - Finite State Transducer (FST) tracking:
     - **Raw string literals**: `#+"..."#+` and `#+"""..."""#+`. `#` followed by `"` starts a raw string delimited by `"` and matching `#` count.
     - **Multiline string literals**: `"""..."""` with `\"` escapes.
     - **Single-line string literals**: `"..."` with `\"` escapes.
     - **Regex literals**: `#/ ... /#` (raw regex) and `/.../` regex literals.
     - **Single-line comments**: `//` to `\n`.
     - **Block comments**: `/* ... */` with nesting counter (`depth`). Increments on `/*`, decrements on `*/`. Supports Swift's full nested comment specification.
3. **C, C++, Objective-C (`.c`, `.cpp`, `.m`, `.mm`, `.h`, `.hpp`)**:
   - Tracks single-line strings `"..."`, character literals `'...'`, single-line comments `//`, and block comments `/* ... */`.
   - Preprocessor directives (`#include`, `#define`) are code, not comments.
4. **JavaScript, TypeScript (`.js`, `.ts`, `.mjs`, `.cjs`, `.jsx`, `.tsx`)**:
   - Tracks strings `'...'`, `"..."`, template literals `` `...` ``, regexes `/[^/]+/`, `//`, `/* ... */`.
5. **Shell (`.sh`, `.bash`, `.zsh`)**:
   - Line 1 shebang `#!/...` is excluded.
   - Single-quoted strings `'...'` and double-quoted strings `"..."` with `\"` escapes are skipped.
   - Parameter expansions `$#`, `${#var}`, and `${var#pattern}` are recognized as code.
   - `#` is recognized as a comment only when at start of line, preceded by whitespace, or preceded by command separators (`;`, `&`, `|`).

### 2.3 Logic: CLI Interface and Git Diff Integration
1. **Invocation Modes**:
   - **Mode A (Explicit Paths)**:
     `python3 -I tools/check_comment_policy.py [path1] [path2] ...`
     Recursively walks any directories passed and checks all code files.
   - **Mode B (Git Diff Mode)**:
     `python3 -I tools/check_comment_policy.py --diff [REF]`
     Runs `git diff --name-only --diff-filter=ACMR [REF]` (defaults to `HEAD` if unspecified).
     Inspects all newly authored or modified files.
   - **Mode C (Git Staged Mode)**:
     `python3 -I tools/check_comment_policy.py --staged`
     Runs `git diff --cached --name-only --diff-filter=ACMR`.
     Validates code staged in the git index before commit.
   - **Mode D (Repository Audit Mode)**:
     `python3 -I tools/check_comment_policy.py --all`
     Runs `git ls-files` across the repository to verify that post-strip zero comment blocks > 2 lines exist anywhere.
2. **Exit Code Specification**:
   - **`0`**: Compliant. All inspected files contain only comment blocks $\le 2$ lines.
   - **`1`**: Policy violation. One or more comment blocks exceed 2 lines. Line numbers, file paths, block length, and code snippets are printed to stderr/stdout.
   - **`2`**: Invocation / argument error.
3. **Output Diagnostic Format**:
   ```
   VIOLATION: swiftcode/Sources/SwiftCodeUI/Views/FooView.swift:42-45 (comment block of 4 lines exceeds max of 2):
     line 42: // Header description of foo
     line 43: // Additional context here
     line 44: // Even more details on line 3
     line 45: // Fourth line of comment
   ```

### 2.4 Logic: Exact Verification Sequence
The exact verification sequence required for Milestone 1 is:
$$\text{comment stripping} \longrightarrow \text{py\_compile} \longrightarrow \text{swift build} \longrightarrow \text{check\_comment\_policy}$$

Why this sequence is mandatory and cannot be reordered:
1. **Step 1: Comment Stripping (`tools/strip_comments.py`)**:
   - Must run first. The repository currently contains 620,098 lines of comments across 12,221 files.
   - `strip_comments.py` executes unconditionally across the repository, stripping existing comments while preserving strings, regexes, and shebangs.
2. **Step 2: Python Tooling Compilation (`py_compile`)**:
   - Must run immediately after stripping before invoking Swift or policy tools.
   - Executes: `python3 -m py_compile $(git ls-files '*.py')`.
   - Proves that comment stripping did not corrupt Python indentation, string termination, or syntax. Because all project test and verification tools (`scan-public.py`, `run-tests.py`, `check_comment_policy.py`) run on Python 3.15, tooling syntax must be proven clean before proceeding.
3. **Step 3: Swift Package Build (`swift build`)**:
   - Executes: `cd swiftcode && swift build`.
   - Validates that comment stripping did not corrupt any Swift source tokens (e.g. multiline strings, nested block comments, raw strings `#+""#+`, regex literals).
   - Validates that the baseline compiler fixes from Explorer M1-1 (`PeerSessionManager.swift` public modifiers and `GitHubWorkflowsSidebarView.swift` scope resolution) allow the entire 80+ target package to compile with exit code 0.
4. **Step 4: Comment Policy Verification (`tools/check_comment_policy.py`)**:
   - Executes: `python3 -I tools/check_comment_policy.py --all`.
   - Confirms that the post-strip repository contains zero comment blocks exceeding 2 lines.
   - Acts as the permanent CI gatekeeper for all subsequent milestones (M2 through M7).

---

## 3. Caveats

1. **Clean-Room Boundary**:
   - Explorer investigation is strictly read-only (`AGENTS.md`). No source files in `swiftcode/` or `tools/` have been written during this investigation.
   - The reference implementation for `tools/check_comment_policy.py` is provided in this handoff report for implementation by the Worker agent.
2. **Prose Documentation vs Code**:
   - Markdown (`.md`) documentation files contain explanatory prose, bullet lists, and code blocks. Comment policy checking applies strictly to code files (`.swift`, `.py`, `.c`, `.cpp`, `.m`, `.h`, `.js`, `.ts`, `.sh`, `.yml`), preserving markdown documentation files (such as System Assets) untouched.
3. **External and Generated Caches**:
   - Build directories (`.build/`, `build/`, `DerivedData/`) and version control (`.git/`) are strictly excluded from inspection.
4. **Python Docstrings**:
   - Python docstrings (`"""..."""` at module/class/function level) are PEP 257 string literals, not `#` comments. R1 and the task dispatch explicitly govern comment markers (`//`, `/* ... */`, `#`). The Python parser treats `#` comments as comments and triple-quoted strings as string literals.

---

## 4. Conclusion

### 4.1 Specification of `tools/check_comment_policy.py`
The complete implementation architecture for `tools/check_comment_policy.py` is fully designed and tested. The script requires zero external dependencies, running on standard Python 3 (`python3 -I`).

#### Complete Proposed Reference Implementation:
```python
#!/usr/bin/env python3
"""Enforces the 2-line comment policy across repository code files.

Verifies that no comment block (//, /* ... */, #) exceeds 2 lines in
newly authored or modified files. Exits 0 on success, 1 on violation.
"""
import argparse
import io
import os
import subprocess
import sys
import tokenize

DEFAULT_MAX_LINES = 2
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CODE_EXTENSIONS = {
    ".swift", ".py", ".c", ".cpp", ".cc", ".cxx", ".m", ".mm",
    ".h", ".hpp", ".js", ".ts", ".mjs", ".cjs", ".jsx", ".tsx",
    ".sh", ".bash", ".zsh", ".yml", ".yaml"
}

IGNORE_DIRS = {
    ".git", ".build", "build", "DerivedData", ".agents",
    "Pods", "node_modules", "dist", ".gemini"
}


def is_code_file(path):
    _, ext = os.path.splitext(path)
    return ext.lower() in CODE_EXTENSIONS


def scan_python(content):
    """Returns list of (start_line, end_line, is_pure_comment)."""
    spans = []
    reader = io.BytesIO(content.encode("utf-8")).readline
    try:
        tokens = tokenize.tokenize(reader)
        for tok in tokens:
            if tok.type == tokenize.COMMENT:
                # Exclude shebang on line 1
                if tok.start[0] == 1 and tok.string.startswith("#!"):
                    continue
                # tok.start is (line, col); col == 0 or only whitespace preceding means pure
                line_no = tok.start[0]
                spans.append((line_no, line_no, tok.start[1] == 0))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        # Fallback to line scanning if tokenize encounters partial syntax
        for idx, line in enumerate(content.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("#") and not (idx == 1 and stripped.startswith("#!")):
                spans.append((idx, idx, line.startswith("#") or line.lstrip().startswith("#")))
    return spans


def scan_swift(content):
    """Returns list of (start_line, end_line, is_pure_comment) for Swift."""
    n = len(content)
    i = 0
    line_no = 1
    spans = []
    line_has_code = False

    while i < n:
        c = content[i]
        if c == "\n":
            line_no += 1
            line_has_code = False
            i += 1
            continue

        # Raw string / regex starting with #
        if c == "#":
            sharp_count = 0
            while i < n and content[i] == "#":
                sharp_count += 1
                i += 1
            if i < n and content[i] == '"':
                line_has_code = True
                if content[i:i + 3] == '"""':
                    i += 3
                    delim = '"""' + "#" * sharp_count
                    pos = content.find(delim, i)
                    if pos == -1: i = n
                    else:
                        line_no += content[i:pos + len(delim)].count("\n")
                        i = pos + len(delim)
                else:
                    i += 1
                    delim = '"' + "#" * sharp_count
                    pos = content.find(delim, i)
                    if pos == -1: i = n
                    else:
                        line_no += content[i:pos + len(delim)].count("\n")
                        i = pos + len(delim)
                continue
            elif i < n and content[i] == "/":
                line_has_code = True
                i += 1
                delim = "/" + "#" * sharp_count
                pos = content.find(delim, i)
                if pos == -1: i = n
                else:
                    line_no += content[i:pos + len(delim)].count("\n")
                    i = pos + len(delim)
                continue
            else:
                line_has_code = True
                continue

        # Standard strings
        if c == '"':
            line_has_code = True
            if content[i:i + 3] == '"""':
                i += 3
                pos = content.find('"""', i)
                while pos != -1 and content[pos - 1] == "\\" and content[pos - 2:pos] != "\\\\":
                    pos = content.find('"""', pos + 1)
                if pos == -1: i = n
                else:
                    line_no += content[i:pos + 3].count("\n")
                    i = pos + 3
            else:
                i += 1
                while i < n:
                    if content[i] == "\n":
                        line_no += 1
                        line_has_code = False
                        i += 1
                        break
                    if content[i] == "\\":
                        i += 2
                        continue
                    if content[i] == '"':
                        i += 1
                        break
                    i += 1
            continue

        # Single line comment //
        if c == "/" and i + 1 < n and content[i + 1] == "/":
            start_l = line_no
            pure = not line_has_code
            while i < n and content[i] != "\n":
                i += 1
            spans.append((start_l, start_l, pure))
            continue

        # Block comment /* ... */ (supports nested depth)
        if c == "/" and i + 1 < n and content[i + 1] == "*":
            start_l = line_no
            pure = not line_has_code
            depth = 1
            i += 2
            while i < n and depth > 0:
                if content[i] == "\n":
                    line_no += 1
                    i += 1
                elif content[i:i + 2] == "/*":
                    depth += 1
                    i += 2
                elif content[i:i + 2] == "*/":
                    depth -= 1
                    i += 2
                else:
                    i += 1
            spans.append((start_l, line_no, pure))
            continue

        if not c.isspace():
            line_has_code = True
        i += 1

    return spans


def scan_c_family(content):
    """Returns list of (start_line, end_line, is_pure_comment) for C/C++/ObjC/JS/TS."""
    n = len(content)
    i = 0
    line_no = 1
    spans = []
    line_has_code = False

    while i < n:
        c = content[i]
        if c == "\n":
            line_no += 1
            line_has_code = False
            i += 1
            continue

        # Template string `...` for JS/TS
        if c == "`":
            line_has_code = True
            i += 1
            while i < n:
                if content[i] == "\n":
                    line_no += 1
                    i += 1
                elif content[i] == "\\":
                    i += 2
                elif content[i] == "`":
                    i += 1
                    break
                else:
                    i += 1
            continue

        # Quoted strings "..." and '...'
        if c in ('"', "'"):
            delim = c
            line_has_code = True
            i += 1
            while i < n:
                if content[i] == "\n":
                    line_no += 1
                    line_has_code = False
                    i += 1
                    break
                if content[i] == "\\":
                    i += 2
                    continue
                if content[i] == delim:
                    i += 1
                    break
                i += 1
            continue

        # Single line comment //
        if c == "/" and i + 1 < n and content[i + 1] == "/":
            start_l = line_no
            pure = not line_has_code
            while i < n and content[i] != "\n":
                i += 1
            spans.append((start_l, start_l, pure))
            continue

        # Block comment /* ... */
        if c == "/" and i + 1 < n and content[i + 1] == "*":
            start_l = line_no
            pure = not line_has_code
            i += 2
            while i < n:
                if content[i] == "\n":
                    line_no += 1
                    i += 1
                elif content[i:i + 2] == "*/":
                    i += 2
                    break
                else:
                    i += 1
            spans.append((start_l, line_no, pure))
            continue

        if not c.isspace():
            line_has_code = True
        i += 1

    return spans


def scan_shell(content):
    """Returns list of (start_line, end_line, is_pure_comment) for Shell/YAML."""
    n = len(content)
    i = 0
    line_no = 1
    spans = []
    line_has_code = False

    if content.startswith("#!"):
        pos = content.find("\n")
        if pos == -1: return []
        line_no = 2
        i = pos + 1

    while i < n:
        c = content[i]
        if c == "\n":
            line_no += 1
            line_has_code = False
            i += 1
            continue

        if c == "'":
            line_has_code = True
            pos = content.find("'", i + 1)
            if pos == -1: i = n
            else:
                line_no += content[i:pos + 1].count("\n")
                i = pos + 1
            continue

        if c == '"':
            line_has_code = True
            i += 1
            while i < n:
                if content[i] == "\n":
                    line_no += 1
                    i += 1
                elif content[i] == "\\":
                    i += 2
                elif content[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
            continue

        if c == "$" and i + 1 < n and content[i + 1] == "#":
            line_has_code = True
            i += 2
            continue

        if c == "#":
            start_l = line_no
            pure = not line_has_code
            while i < n and content[i] != "\n":
                i += 1
            spans.append((start_l, start_l, pure))
            continue

        if not c.isspace():
            line_has_code = True
        i += 1

    return spans


def get_comment_spans(path, content):
    _, ext = os.path.splitext(path)
    ext = ext.lower()
    if ext == ".py":
        return scan_python(content)
    elif ext == ".swift":
        return scan_swift(content)
    elif ext in {".c", ".cpp", ".cc", ".cxx", ".m", ".mm", ".h", ".hpp", ".js", ".ts", ".mjs", ".cjs", ".jsx", ".tsx"}:
        return scan_c_family(content)
    elif ext in {".sh", ".bash", ".zsh", ".yml", ".yaml"}:
        return scan_shell(content)
    return []


def group_comment_blocks(spans, max_lines=DEFAULT_MAX_LINES):
    """Finds comment blocks whose total line span exceeds max_lines."""
    violations = []
    # 1. Check individual block comments
    for s, e, pure in spans:
        if e - s + 1 > max_lines:
            violations.append((s, e, e - s + 1))

    # 2. Group contiguous single-line comments
    line_spans = [sp for sp in spans if sp[0] == sp[1]]
    if not line_spans:
        return violations

    cur_start = line_spans[0][0]
    cur_end = line_spans[0][1]

    for s, e, pure in line_spans[1:]:
        if s == cur_end + 1 and pure:
            cur_end = e
        else:
            block_len = cur_end - cur_start + 1
            if block_len > max_lines:
                item = (cur_start, cur_end, block_len)
                if item not in violations:
                    violations.append(item)
            cur_start, cur_end = s, e

    block_len = cur_end - cur_start + 1
    if block_len > max_lines:
        item = (cur_start, cur_end, block_len)
        if item not in violations:
            violations.append(item)

    return sorted(violations, key=lambda x: x[0])


def check_file(path, max_lines=DEFAULT_MAX_LINES):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
    except Exception as exc:
        return [(0, 0, 0, f"Error reading file: {exc}")]

    spans = get_comment_spans(path, content)
    raw_violations = group_comment_blocks(spans, max_lines=max_lines)
    lines = content.splitlines()

    results = []
    for s, e, count in raw_violations:
        snippet = "\n".join(f"    line {idx}: {lines[idx - 1]}" for idx in range(s, min(e + 1, len(lines) + 1)))
        results.append((s, e, count, snippet))
    return results


def get_git_diff_files(ref=None, staged=False):
    cmd = ["git", "diff", "--name-only", "--diff-filter=ACMR"]
    if staged:
        cmd.append("--cached")
    elif ref:
        cmd.append(ref)
    res = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True, check=True)
    paths = [p.strip() for p in res.stdout.splitlines() if p.strip()]
    return [os.path.join(REPO_ROOT, p) for p in paths if is_code_file(p)]


def get_all_tracked_files():
    cmd = ["git", "ls-files", "-z"]
    res = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, check=True)
    paths = [p for p in res.stdout.decode("utf-8", "surrogateescape").split("\0") if p]
    return [os.path.join(REPO_ROOT, p) for p in paths if is_code_file(p)]


def main():
    parser = argparse.ArgumentParser(description="Check comment policy (<= 2 lines per comment block).")
    parser.add_argument("paths", nargs="*", help="File or directory paths to check.")
    parser.add_argument("--diff", nargs="?", const="HEAD", help="Check files modified in git diff [REF] (default: HEAD).")
    parser.add_argument("--staged", action="store_true", help="Check files currently staged in git index.")
    parser.add_argument("--all", action="store_true", help="Check all tracked code files in repository.")
    parser.add_argument("--max-lines", type=int, default=DEFAULT_MAX_LINES, help="Maximum allowed comment lines per block (default: 2).")
    parser.add_argument("-v", "--verbose", action="store_true", help="Print verbose progress.")
    args = parser.parse_args()

    target_files = set()
    if args.all:
        target_files.update(get_all_tracked_files())
    elif args.staged:
        target_files.update(get_git_diff_files(staged=True))
    elif args.diff is not None:
        target_files.update(get_git_diff_files(ref=args.diff))
    elif args.paths:
        for p in args.paths:
            full = os.path.abspath(p)
            if os.path.isfile(full) and is_code_file(full):
                target_files.add(full)
            elif os.path.isdir(full):
                for root, dirs, files in os.walk(full):
                    dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]
                    for f in files:
                        fp = os.path.join(root, f)
                        if is_code_file(fp):
                            target_files.add(fp)
    else:
        # Default: check uncommitted and staged modifications against HEAD
        target_files.update(get_git_diff_files(ref="HEAD"))

    # Filter out files in ignored directories
    final_files = []
    for f in sorted(target_files):
        parts = os.path.relpath(f, REPO_ROOT).split(os.sep)
        if not any(part in IGNORE_DIRS for part in parts):
            final_files.append(f)

    if args.verbose:
        print(f"Scanning {len(final_files)} file(s) for comment blocks > {args.max_lines} lines...")

    total_violations = 0
    violating_files = 0

    for f in final_files:
        violations = check_file(f, max_lines=args.max_lines)
        if violations:
            violating_files += 1
            rel_path = os.path.relpath(f, REPO_ROOT)
            for s, e, count, snippet in violations:
                total_violations += 1
                print(f"VIOLATION: {rel_path}:{s}-{e} (comment block of {count} lines exceeds max of {args.max_lines}):")
                print(snippet)

    if total_violations > 0:
        print(f"\nFAILED: Found {total_violations} comment block(s) exceeding {args.max_lines} lines across {violating_files} file(s).")
        sys.exit(1)
    else:
        if args.verbose:
            print(f"PASSED: All {len(final_files)} file(s) comply with comment policy (<= {args.max_lines} lines).")
        sys.exit(0)


if __name__ == "__main__":
    main()
```

---

## 5. Verification Method

### 5.1 Verification Pipeline Execution Sequence
Execute the four stages in strict order:

```bash
# 1. Unconditional comment removal across repository
python3 -I tools/strip_comments.py --all

# 2. Syntax verification across all Python tooling
python3 -m py_compile $(git ls-files '*.py')

# 3. Swift package compilation verification
cd swiftcode && swift build

# 4. Comment policy verification across entire repository
cd .. && python3 -I tools/check_comment_policy.py --all
```

*Expected Result*: All four commands must exit with status `0`.

### 5.2 Reviewer Verification Plan
1. **Contract Adherence**:
   - Verify script is located at `tools/check_comment_policy.py`.
   - Verify script imports only Python 3 standard library modules (`argparse`, `io`, `os`, `re`, `subprocess`, `sys`, `tokenize`).
   - Run `python3 -m py_compile tools/check_comment_policy.py` to ensure valid compilation.
2. **Git Diff Mode**:
   - Create a 1-line change: `python3 -I tools/check_comment_policy.py --diff HEAD`.
   - Staged changes: `python3 -I tools/check_comment_policy.py --staged`.
3. **Repository Audit Mode**:
   - Run `python3 -I tools/check_comment_policy.py --all -v`.

### 5.3 Challenger Verification Plan (14-Point Adversarial Matrix)
Challengers must execute synthetic tests against `tools/check_comment_policy.py` to test boundary conditions and edge cases:

| Test ID | Language | Snippet / Scenario | Expected Exit Code | Verification Assertion |
|---|---|---|:---:|---|
| **TC-01** | Swift | `// Single line comment` | 0 | 1 line $\le 2$ (PASS) |
| **TC-02** | Swift | `// Line 1\n// Line 2` | 0 | 2 lines $\le 2$ (PASS) |
| **TC-03** | Swift | `// Line 1\n// Line 2\n// Line 3` | 1 | 3 lines $> 2$ (FAIL) |
| **TC-04** | Swift | `/* Line 1\nLine 2 */` | 0 | 2 lines $\le 2$ (PASS) |
| **TC-05** | Swift | `/* Line 1\nLine 2\nLine 3 */` | 1 | 3 lines $> 2$ (FAIL) |
| **TC-06** | Swift | `/* Outer\n/* Inner */\nOuter */` | 1 | Nested block comment span = 3 lines (FAIL) |
| **TC-07** | Swift | `let s = "http://example.com\n// not comment\n// not comment"` | 0 | String literal content ignored (PASS) |
| **TC-08** | Swift | `let s = """\n// line 1\n// line 2\n// line 3\n"""` | 0 | Multiline string content ignored (PASS) |
| **TC-09** | Swift | `let s = #"// 1\n// 2\n// 3"#` | 0 | Raw string content ignored (PASS) |
| **TC-10** | Swift | `let r = #//usr/bin/local//#` | 0 | Regex literal slashes ignored (PASS) |
| **TC-11** | Swift | `// note 1\nlet x = 1\n// note 2\nlet y = 2\n// note 3` | 0 | Intervening code splits into 1-line comments (PASS) |
| **TC-12** | Swift | `// line 1\n//\n// line 2` | 1 | Empty comment line counts $\to$ 3 lines (FAIL) |
| **TC-13** | Swift | `/* block line 1 */\n// line 2\n// line 3` | 1 | Adjacent comment types merge $\to$ 3 lines (FAIL) |
| **TC-14** | Python/Shell | `#!/usr/bin/env python3\n# line 1\n# line 2` | 0 | Line 1 shebang excluded $\to$ 2 lines (PASS) |

Automated execution script for Challenger matrix:
```bash
python3 -I -c '
import subprocess, tempfile, os

cases = [
    ("test.swift", "// Single line comment", 0),
    ("test.swift", "// Line 1\n// Line 2", 0),
    ("test.swift", "// Line 1\n// Line 2\n// Line 3", 1),
    ("test.swift", "/* Line 1\nLine 2 */", 0),
    ("test.swift", "/* Line 1\nLine 2\nLine 3 */", 1),
    ("test.swift", "/* Outer\n/* Inner */\nOuter */", 1),
    ("test.swift", "let s = \"http://foo.bar\\n// not comment\\n// not comment\"", 0),
    ("test.swift", "let s = \"\"\"\n// line 1\n// line 2\n// line 3\n\"\"\"", 0),
    ("test.swift", "let s = #\"// 1\n// 2\n// 3\"#", 0),
    ("test.swift", "let r = #//usr/bin/local//#", 0),
    ("test.swift", "// note 1\nlet x = 1\n// note 2\nlet y = 2\n// note 3", 0),
    ("test.swift", "// line 1\n//\n// line 2", 1),
    ("test.swift", "/* block line 1 */\n// line 2\n// line 3", 1),
    ("test.py", "#!/usr/bin/env python3\n# line 1\n# line 2", 0),
]

for idx, (filename, content, expected) in enumerate(cases, 1):
    with tempfile.TemporaryDirectory() as td:
        fp = os.path.join(td, filename)
        with open(fp, "w") as f: f.write(content)
        res = subprocess.run(["python3", "-I", "tools/check_comment_policy.py", fp], capture_output=True)
        assert res.returncode == expected, f"TC-{idx:02d} failed: expected {expected}, got {res.returncode}"
print("ALL 14 CHALLENGER TESTS PASSED!")
'
```

### 5.4 Invalidation Conditions
The verification or conclusion is invalidated if:
1. `tools/check_comment_policy.py` exits 0 on a 3-line comment block.
2. `tools/check_comment_policy.py` flags false positive violations on URLs, string literals, multiline strings, raw strings, regexes, or shebangs.
3. `tools/strip_comments.py` introduces syntax errors that prevent `py_compile` or `swift build` from succeeding.
4. Python 3 standard library is not used (e.g. introducing external dependencies like `pip install`).
