#!/usr/bin/env python3
"""Multi-language comment stripping engine for SwiftCode."""

import argparse
import difflib
import io
import os
import re
import sys
import tokenize

EXCLUDED_DIRS = {
    ".git", ".build", "build", "DerivedData", "node_modules",
    ".agents", "xcuserdata", "__pycache__", ".pytest_cache",
    ".mypy_cache", ".swiftpm", ".build-ide", ".venv", "venv",
}

EXCLUDED_EXTENSIONS = {
    ".dylib", ".so", ".a", ".o", ".tbd", ".dSYM", ".framework",
    ".xcframework", ".bin", ".dat", ".car", ".ipa", ".dmg", ".pkg",
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".icns", ".tiff", ".webp", ".pdf",
    ".mp3", ".wav", ".m4a", ".mp4", ".mov", ".ttf", ".otf", ".woff", ".woff2",
    ".zip", ".tar", ".gz", ".tgz", ".bz2", ".xz",
    ".sqlite", ".sqlite3", ".db", ".cer", ".p12", ".pem", ".mobileprovision",
    ".pbxproj", ".json", ".plist", ".strings", ".md", ".markdown",
    ".gitkeep", ".gitignore", ".gitattributes", ".gitmodules",
}

def is_binary(raw_bytes: bytes) -> bool:
    if b"\x00" in raw_bytes[:1024]:
        return True
    try:
        raw_bytes[:4096].decode("utf-8")
        return False
    except UnicodeDecodeError:
        return True

def collapse_newlines(text: str) -> str:
    lines = [line.rstrip() for line in text.splitlines()]
    res = "\n".join(lines)
    res = re.sub(r"\n{3,}", "\n\n", res)
    if res.strip():
        res = res.strip("\n") + "\n"
    elif res:
        res = "\n"
    return res

def strip_python_comments(src: str) -> str:
    lines = src.splitlines(keepends=True)
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(src).readline))
    except Exception:
        return src

    comment_tokens = [
        t for t in tokens
        if t.type == tokenize.COMMENT and not (t.start[0] == 1 and t.string.startswith("#!"))
    ]
    if not comment_tokens:
        return src

    comments_by_line = {t.start[0]: t for t in comment_tokens}
    out_lines = []
    for idx, line in enumerate(lines, 1):
        if idx in comments_by_line:
            t = comments_by_line[idx]
            prefix = line[:t.start[1]]
            if prefix.strip() == "":
                continue
            out_lines.append(prefix.rstrip() + "\n")
        else:
            out_lines.append(line)

    return collapse_newlines("".join(out_lines))

def strip_swift_comments(src: str) -> str:
    out = []
    i = 0
    n = len(src)
    line_buf = []
    has_code = False

    def flush_line():
        nonlocal line_buf, has_code
        out.extend(line_buf)
        line_buf = []
        has_code = False

    if src.startswith("// swift-tools-version:"):
        nl = src.find("\n")
        if nl == -1:
            return src
        out.append(src[:nl + 1])
        i = nl + 1

    while i < n:
        if src[i] == "#":
            h = 0
            while i + h < n and src[i + h] == "#":
                h += 1
            after_h = i + h
            if after_h < n and src[after_h:after_h + 3] == '"""':
                delim = '"""' + "#" * h
                line_buf.append(src[i:after_h + 3])
                has_code = True
                i = after_h + 3
                while i < n:
                    if src[i:i + len(delim)] == delim:
                        line_buf.append(delim)
                        i += len(delim)
                        break
                    if src[i] == "\n":
                        line_buf.append("\n")
                        flush_line()
                        has_code = True
                        i += 1
                    else:
                        line_buf.append(src[i])
                        i += 1
                continue
            elif after_h < n and src[after_h] == '"':
                delim = '"' + "#" * h
                line_buf.append(src[i:after_h + 1])
                has_code = True
                i = after_h + 1
                while i < n:
                    if src[i:i + len(delim)] == delim:
                        line_buf.append(delim)
                        i += len(delim)
                        break
                    if src[i] == "\n":
                        line_buf.append("\n")
                        flush_line()
                        has_code = True
                        i += 1
                    else:
                        line_buf.append(src[i])
                        i += 1
                continue
            elif after_h < n and src[after_h] == "/":
                delim = "/" + "#" * h
                line_buf.append(src[i:after_h + 1])
                has_code = True
                i = after_h + 1
                while i < n:
                    if src[i] == "\\":
                        line_buf.append(src[i:i + 2])
                        i += 2
                        continue
                    if src[i:i + len(delim)] == delim:
                        line_buf.append(delim)
                        i += len(delim)
                        break
                    line_buf.append(src[i])
                    i += 1
                continue
            else:
                line_buf.append(src[i:after_h])
                has_code = True
                i = after_h
                continue

        if src[i:i + 3] == '"""':
            line_buf.append('"""')
            has_code = True
            i += 3
            while i < n:
                if src[i] == "\\":
                    line_buf.append(src[i:i + 2])
                    i += 2
                    continue
                if src[i:i + 3] == '"""':
                    line_buf.append('"""')
                    i += 3
                    break
                if src[i] == "\n":
                    line_buf.append("\n")
                    flush_line()
                    has_code = True
                    i += 1
                else:
                    line_buf.append(src[i])
                    i += 1
            continue

        if src[i] == '"':
            line_buf.append('"')
            has_code = True
            i += 1
            while i < n:
                if src[i] == "\\":
                    line_buf.append(src[i:i + 2])
                    i += 2
                    continue
                if src[i] == '"':
                    line_buf.append('"')
                    i += 1
                    break
                if src[i] == "\n":
                    break
                line_buf.append(src[i])
                i += 1
            continue

        if src[i:i + 2] == "//":
            i += 2
            while i < n and src[i] != "\n":
                i += 1
            if not has_code:
                line_buf = []
                if i < n and src[i] == "\n":
                    i += 1
            continue

        if src[i:i + 2] == "/*":
            depth = 1
            i += 2
            while i < n and depth > 0:
                if src[i:i + 2] == "/*":
                    depth += 1
                    i += 2
                elif src[i:i + 2] == "*/":
                    depth -= 1
                    i += 2
                else:
                    i += 1
            if not has_code:
                rem_ws = True
                j = i
                while j < n and src[j] != "\n":
                    if src[j] not in " \t\r":
                        rem_ws = False
                        break
                    j += 1
                if rem_ws:
                    line_buf = []
                    i = j
                    if i < n and src[i] == "\n":
                        i += 1
            continue

        c = src[i]
        if c == "\n":
            line_buf.append("\n")
            flush_line()
            i += 1
        elif c in " \t\r":
            line_buf.append(c)
            i += 1
        else:
            line_buf.append(c)
            has_code = True
            i += 1

    flush_line()
    return collapse_newlines("".join(out))

def strip_c_comments(src: str) -> str:
    out = []
    i = 0
    n = len(src)
    line_buf = []
    has_code = False

    def flush_line():
        nonlocal line_buf, has_code
        out.extend(line_buf)
        line_buf = []
        has_code = False

    while i < n:
        c = src[i]
        if c == '"' or (c == "@" and i + 1 < n and src[i + 1] == '"'):
            if c == "@":
                line_buf.append('@"')
                i += 2
            else:
                line_buf.append('"')
                i += 1
            has_code = True
            while i < n:
                if src[i] == "\\":
                    line_buf.append(src[i:i + 2])
                    i += 2
                    continue
                if src[i] == '"':
                    line_buf.append('"')
                    i += 1
                    break
                if src[i] == "\n":
                    break
                line_buf.append(src[i])
                i += 1
            continue

        if c == "'":
            line_buf.append("'")
            has_code = True
            i += 1
            while i < n:
                if src[i] == "\\":
                    line_buf.append(src[i:i + 2])
                    i += 2
                    continue
                if src[i] == "'":
                    line_buf.append("'")
                    i += 1
                    break
                if src[i] == "\n":
                    break
                line_buf.append(src[i])
                i += 1
            continue

        if src[i:i + 2] == "//":
            i += 2
            while i < n and src[i] != "\n":
                i += 1
            if not has_code:
                line_buf = []
                if i < n and src[i] == "\n":
                    i += 1
            continue

        if src[i:i + 2] == "/*":
            i += 2
            while i < n and src[i:i + 2] != "*/":
                i += 1
            if i < n:
                i += 2
            if not has_code:
                rem_ws = True
                j = i
                while j < n and src[j] != "\n":
                    if src[j] not in " \t\r":
                        rem_ws = False
                        break
                    j += 1
                if rem_ws:
                    line_buf = []
                    i = j
                    if i < n and src[i] == "\n":
                        i += 1
            continue

        if c == "\n":
            line_buf.append("\n")
            flush_line()
            i += 1
        elif c in " \t\r":
            line_buf.append(c)
            i += 1
        else:
            line_buf.append(c)
            has_code = True
            i += 1

    flush_line()
    return collapse_newlines("".join(out))

def strip_js_ts_comments(src: str) -> str:
    out = []
    i = 0
    n = len(src)
    line_buf = []
    has_code = False

    def flush_line():
        nonlocal line_buf, has_code
        out.extend(line_buf)
        line_buf = []
        has_code = False

    while i < n:
        c = src[i]
        if c == "`":
            line_buf.append("`")
            has_code = True
            i += 1
            while i < n:
                if src[i] == "\\":
                    line_buf.append(src[i:i + 2])
                    i += 2
                    continue
                if src[i] == "`":
                    line_buf.append("`")
                    i += 1
                    break
                if src[i] == "\n":
                    line_buf.append("\n")
                    flush_line()
                    has_code = True
                    i += 1
                else:
                    line_buf.append(src[i])
                    i += 1
            continue

        if c in ("'", '"'):
            quote = c
            line_buf.append(quote)
            has_code = True
            i += 1
            while i < n:
                if src[i] == "\\":
                    line_buf.append(src[i:i + 2])
                    i += 2
                    continue
                if src[i] == quote:
                    line_buf.append(quote)
                    i += 1
                    break
                if src[i] == "\n":
                    break
                line_buf.append(src[i])
                i += 1
            continue

        if src[i:i + 2] == "//":
            i += 2
            while i < n and src[i] != "\n":
                i += 1
            if not has_code:
                line_buf = []
                if i < n and src[i] == "\n":
                    i += 1
            continue

        if src[i:i + 2] == "/*":
            i += 2
            while i < n and src[i:i + 2] != "*/":
                i += 1
            if i < n:
                i += 2
            if not has_code:
                rem_ws = True
                j = i
                while j < n and src[j] != "\n":
                    if src[j] not in " \t\r":
                        rem_ws = False
                        break
                    j += 1
                if rem_ws:
                    line_buf = []
                    i = j
                    if i < n and src[i] == "\n":
                        i += 1
            continue

        if c == "\n":
            line_buf.append("\n")
            flush_line()
            i += 1
        elif c in " \t\r":
            line_buf.append(c)
            i += 1
        else:
            line_buf.append(c)
            has_code = True
            i += 1

    flush_line()
    return collapse_newlines("".join(out))

def strip_shell_comments(src: str) -> str:
    lines = src.splitlines(keepends=True)
    out = []
    for idx, line in enumerate(lines):
        if idx == 0 and line.startswith("#!"):
            out.append(line)
            continue
        res = []
        i = 0
        n = len(line)
        in_s = False
        in_d = False
        param_depth = 0
        has_code = False
        while i < n:
            c = line[i]
            if c == "\\" and not in_s and i + 1 < n:
                res.append(line[i:i + 2])
                has_code = True
                i += 2
                continue
            if c == "'" and not in_d:
                in_s = not in_s
                res.append(c)
                has_code = True
                i += 1
                continue
            if c == '"' and not in_s:
                in_d = not in_d
                res.append(c)
                has_code = True
                i += 1
                continue
            if not in_s and not in_d:
                if line[i:i + 2] == "${":
                    param_depth += 1
                    res.append("${")
                    has_code = True
                    i += 2
                    continue
                elif c == "}" and param_depth > 0:
                    param_depth -= 1
                    res.append("}")
                    has_code = True
                    i += 1
                    continue
                if line[i:i + 2] == "$#":
                    res.append("$#")
                    has_code = True
                    i += 2
                    continue
                if param_depth > 0 and c == "#":
                    res.append("#")
                    has_code = True
                    i += 1
                    continue
                if c == "#":
                    prev = line[i - 1] if i > 0 else " "
                    if prev in " \t;&|()<>":
                        break
                    else:
                        res.append(c)
                        has_code = True
                        i += 1
                        continue
            res.append(c)
            if c not in " \t\r\n":
                has_code = True
            i += 1
        s = "".join(res)
        if not has_code and s.strip() == "":
            continue
        out.append(s.rstrip() + "\n")

    return collapse_newlines("".join(out))

def strip_file_comments(path: str, content: str) -> str:
    ext = os.path.splitext(path)[1].lower()

    if ext == ".py":
        return strip_python_comments(content)
    elif ext == ".swift":
        return strip_swift_comments(content)
    elif ext in (".c", ".h", ".cpp", ".cc", ".m", ".mm"):
        return strip_c_comments(content)
    elif ext in (".js", ".ts", ".mjs", ".jsx", ".tsx"):
        return strip_js_ts_comments(content)
    elif ext in (".sh", ".bash", ".zsh", ".yml", ".yaml"):
        return strip_shell_comments(content)
    elif not ext and content.startswith("#!"):
        first_line = content.splitlines()[0]
        if "python" in first_line:
            return strip_python_comments(content)
        elif any(sh in first_line for sh in ("sh", "bash", "zsh")):
            return strip_shell_comments(content)

    return content

def should_process_file(rel_path: str) -> bool:
    parts = rel_path.split(os.sep)
    if any(p in EXCLUDED_DIRS for p in parts):
        return False
    _, ext = os.path.splitext(rel_path)
    if ext.lower() in EXCLUDED_EXTENSIONS:
        return False
    return True

def collect_files(repo_root: str, paths=None, all_flag=False):
    targets = []
    if paths:
        for p in paths:
            abs_p = os.path.abspath(p)
            if os.path.isfile(abs_p):
                rel_p = os.path.relpath(abs_p, repo_root)
                if should_process_file(rel_p):
                    targets.append(abs_p)
            elif os.path.isdir(abs_p):
                for root, dirs, files in os.walk(abs_p):
                    dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
                    for f in files:
                        fp = os.path.join(root, f)
                        rel_p = os.path.relpath(fp, repo_root)
                        if should_process_file(rel_p):
                            targets.append(fp)
    else:
        for root, dirs, files in os.walk(repo_root):
            dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
            for f in files:
                fp = os.path.join(root, f)
                rel_p = os.path.relpath(fp, repo_root)
                if should_process_file(rel_p):
                    targets.append(fp)
    return sorted(targets)

def main():
    parser = argparse.ArgumentParser(description="Multi-language comment stripping engine.")
    parser.add_argument("paths", nargs="*", help="Specific files or directories to process.")
    parser.add_argument("--dry-run", action="store_true", help="Report files that would change without modifying.")
    parser.add_argument("--diff", action="store_true", help="Display diffs of proposed changes.")
    parser.add_argument("--check", action="store_true", help="Exit 1 if any files have strippable comments, 0 otherwise.")
    parser.add_argument("--all", action="store_true", help="Scan repository-wide.")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose progress.")
    args = parser.parse_args()

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    target_files = collect_files(repo_root, paths=args.paths, all_flag=args.all)

    modified_count = 0
    total_scanned = 0

    for file_path in target_files:
        try:
            with open(file_path, "rb") as bf:
                raw = bf.read()
            if is_binary(raw):
                continue
            content = raw.decode("utf-8")
        except Exception:
            continue

        total_scanned += 1
        stripped = strip_file_comments(file_path, content)

        if stripped != content:
            modified_count += 1
            rel_p = os.path.relpath(file_path, repo_root)
            if args.verbose or args.dry_run:
                print(f"Strippable: {rel_p}")
            if args.diff:
                diff = difflib.unified_diff(
                    content.splitlines(keepends=True),
                    stripped.splitlines(keepends=True),
                    fromfile=f"a/{rel_p}",
                    tofile=f"b/{rel_p}"
                )
                sys.stdout.writelines(diff)
            if not (args.dry_run or args.check):
                with open(file_path, "w", encoding="utf-8") as wf:
                    wf.write(stripped)

    if args.verbose:
        print(f"Scanned {total_scanned} files. Modified / strippable: {modified_count} files.")

    if args.check:
        if modified_count > 0:
            print(f"Found {modified_count} files with comments.")
            sys.exit(1)
        else:
            print("All scanned files are clean.")
            sys.exit(0)

if __name__ == "__main__":
    main()
