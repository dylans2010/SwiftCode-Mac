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
                if tok.start[0] == 1 and tok.string.startswith("#!"):
                    continue
                line_no = tok.start[0]
                spans.append((line_no, line_no, tok.start[1] == 0))
    except (tokenize.TokenError, IndentationError, SyntaxError):
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

        if c == "/" and i + 1 < n and content[i + 1] == "/":
            start_l = line_no
            pure = not line_has_code
            while i < n and content[i] != "\n":
                i += 1
            spans.append((start_l, start_l, pure))
            continue

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

        if c == "/" and i + 1 < n and content[i + 1] == "/":
            start_l = line_no
            pure = not line_has_code
            while i < n and content[i] != "\n":
                i += 1
            spans.append((start_l, start_l, pure))
            continue

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
    for s, e, pure in spans:
        if e - s + 1 > max_lines:
            violations.append((s, e, e - s + 1))

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
    if not os.path.exists(path):
        return []
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
    return [os.path.join(REPO_ROOT, p) for p in paths if is_code_file(p) and os.path.exists(os.path.join(REPO_ROOT, p))]

def get_all_tracked_files():
    cmd = ["git", "ls-files", "-z"]
    res = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, check=True)
    paths = [p for p in res.stdout.decode("utf-8", "surrogateescape").split("\0") if p]
    return [os.path.join(REPO_ROOT, p) for p in paths if is_code_file(p) and os.path.exists(os.path.join(REPO_ROOT, p))]

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
        target_files.update(get_git_diff_files(ref="HEAD"))

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
