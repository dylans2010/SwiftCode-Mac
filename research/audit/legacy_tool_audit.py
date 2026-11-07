#!/usr/bin/env python3
import re, os, json, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LEGACY = os.path.join(ROOT, "SwiftCode-Legacy", "SwiftCode", "Backend", "Assist")
PROD = os.path.join(ROOT, "swiftcode", "Sources")

def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()

reg = read(os.path.join(LEGACY, "AssistToolRegistry.swift"))
legacy_registered = re.findall(r"^\s*register\((\w+)\(\)\)", reg, re.M)

tool_files = {}
for base, _, files in os.walk(os.path.join(LEGACY, "Tools")):
    for fn in files:
        if fn.endswith(".swift"):
            tool_files[fn] = os.path.join(base, fn)

type_files = {}
for base, _, files in os.walk(LEGACY):
    for fn in files:
        if not fn.endswith(".swift"):
            continue
        p = os.path.join(base, fn)
        src = read(p)
        for m in re.finditer(r"(?:final\s+)?(?:class|struct)\s+(\w+)\s*:[^{]*\bAssistTool\b", src):
            type_files.setdefault(m.group(1), p)

ids = {}
for t in legacy_registered:
    p = type_files.get(t)
    if not p:
        ids[t] = None
        continue
    src = read(p)
    m = re.search(r"var\s+id\s*:\s*String\s*\{\s*\"([^\"]+)\"", src)
    ids[t] = m.group(1) if m else "?"

prod_types = {}
prod_ids = {}
for base, _, files in os.walk(PROD):
    for fn in files:
        if not fn.endswith(".swift"):
            continue
        p = os.path.join(base, fn)
        src = read(p)
        for m in re.finditer(r"(?:final\s+)?(?:class|struct)\s+(\w+)\s*:[^{]*\bAssistTool\b", src):
            prod_types.setdefault(m.group(1), p)
        for m in re.finditer(r"var\s+id\s*:\s*String\s*\{\s*\"([^\"]+)\"", src):
            prod_ids.setdefault(m.group(1), p)

missing_type = [t for t in legacy_registered if t not in prod_types]
present_type = [t for t in legacy_registered if t in prod_types]
legacy_ids = sorted({v for v in ids.values() if v and v != "?"})
prod_id_set = set(prod_ids)
missing_id = [i for i in legacy_ids if i not in prod_id_set]

mcp_dir = os.path.join(PROD, "SwiftCodeMCP", "Tools")
mcp_names = set()
for base, _, files in os.walk(mcp_dir):
    for fn in files:
        if fn.endswith(".swift"):
            src = read(os.path.join(base, fn))
            for m in re.finditer(r"name:\s*\"([a-z0-9_\-\.]+)\"", src):
                mcp_names.add(m.group(1))

out = {
    "legacy_registered_count": len(legacy_registered),
    "legacy_unique_ids": len(legacy_ids),
    "legacy_tool_files": len(tool_files),
    "prod_assist_types": len(prod_types),
    "prod_item_ids": len(prod_id_set),
    "mcp_names": len(mcp_names),
    "missing_type_count": len(missing_type),
    "missing_id_count": len(missing_id),
    "missing_types": missing_type,
    "missing_ids": missing_id,
    "legacy_ids": legacy_ids,
}
print(json.dumps({k: v for k, v in out.items() if not isinstance(v, list)}, indent=2))
print("\nMISSING TYPES (%d):" % len(missing_type))
print("\n".join(missing_type))
print("\nMISSING PROD IDS (%d) of %d:" % (len(missing_id), len(legacy_ids)))
print("\n".join(missing_id))
