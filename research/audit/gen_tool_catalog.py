#!/usr/bin/env python3
import os, re, json

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LEGACY = os.path.join(ROOT, "SwiftCode-Legacy", "SwiftCode", "Backend", "Assist")
OUT = os.path.join(ROOT, "swiftcode", "Sources", "SwiftCodeAssistant", "Tools", "AssistToolCatalog.swift")

BLOCK = re.compile(r"public\s+(?:final\s+)?(?:struct|class)\s+(\w+)\s*:\s*[^{]*\bAssistTool\b", re.M)

def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()

entries = []
seen = set()

for base, _, files in sorted(os.walk(LEGACY)):
    for fn in sorted(files):
        if not fn.endswith(".swift"):
            continue
        src = read(os.path.join(base, fn))
        starts = [(m.start(), m.group(1)) for m in BLOCK.finditer(src)]
        for i, (pos, tname) in enumerate(starts):
            end = starts[i + 1][0] if i + 1 < len(starts) else len(src)
            block = src[pos:end]
            idm = re.search(r'(?:public\s+)?let\s+id\s*(?::\s*String\s*)?=\s*"([^"]+)"', block)
            if not idm:
                idm = re.search(r'(?:public\s+)?var\s+id\s*:\s*String\s*\{\s*"([^"]+)"', block)
            namem = re.search(r'(?:public\s+)?let\s+name\s*(?::\s*String\s*)?=\s*"([^"]*)"', block)
            descm = re.search(r'(?:public\s+)?let\s+description\s*(?::\s*String\s*)?=\s*"([^"]*)"', block)
            if not idm:
                continue
            tid = idm.group(1)
            if tid in seen:
                continue
            seen.add(tid)
            entries.append({
                "id": tid,
                "name": (namem.group(1) if namem else tname),
                "summary": (descm.group(1).replace("\\", "\\\\").replace('"', '\\"') if descm else ""),
                "type": tname,
            })

entries.sort(key=lambda e: e["id"])

lines = []
lines.append("import Foundation")
lines.append("")
lines.append("public struct AssistToolCatalogEntry: Sendable, Hashable {")
lines.append("    public let id: String")
lines.append("    public let name: String")
lines.append("    public let summary: String")
lines.append("    public let sourceType: String")
lines.append("")
lines.append("    public init(id: String, name: String, summary: String, sourceType: String) {")
lines.append("        self.id = id")
lines.append("        self.name = name")
lines.append("        self.summary = summary")
lines.append("        self.sourceType = sourceType")
lines.append("    }")
lines.append("}")
lines.append("")
lines.append("public enum AssistToolCatalog {")
lines.append('    public static let origin = "SwiftCode-Legacy/SwiftCode/Backend/Assist"')
lines.append("")
lines.append("    public static let entries: [AssistToolCatalogEntry] = [")
for e in entries:
    n = e["name"].replace("\\", "\\\\").replace('"', '\\"')
    lines.append('        AssistToolCatalogEntry(id: "%s", name: "%s", summary: "%s", sourceType: "%s"),' % (e["id"], n, e["summary"], e["type"]))
lines.append("    ]")
lines.append("")
lines.append("    public static let ids: Set<String> = Set(entries.map(\\.id))")
lines.append("")
lines.append("    public static func contains(_ id: String) -> Bool { ids.contains(id) }")
lines.append("")
lines.append("    public static func entry(for id: String) -> AssistToolCatalogEntry? { entries.first { $0.id == id } }")
lines.append("}")
lines.append("")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print("entries:", len(entries))
print("written:", OUT)
with open(os.path.join(ROOT, "research", "audit", "legacy_tool_catalog.json"), "w", encoding="utf-8") as f:
    json.dump(entries, f, indent=2)
