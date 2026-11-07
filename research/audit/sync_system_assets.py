#!/usr/bin/env python3
import os, shutil, re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "SwiftCode-Legacy", "SwiftCode", "Backend", "Assist", "Functions", "System Assets")
DST = os.path.join(ROOT, "swiftcode", "Sources", "SwiftCodeAssistant", "Resources", "System Assets")

os.makedirs(DST, exist_ok=True)
copied = 0
for name in sorted(os.listdir(SRC)):
    if not name.endswith(".md"):
        continue
    with open(os.path.join(SRC, name), encoding="utf-8", errors="replace") as f:
        text = f.read()
    text = text.replace("Coding Assistant", "Assist").replace("Assistant", "Assist")
    text = re.sub(r"Assist(s)? Settings", r"Assist\1 Settings", text)
    with open(os.path.join(DST, name), "w", encoding="utf-8") as f:
        f.write(text)
    copied += 1

extra = sorted(set(os.listdir(DST)) - set(os.listdir(SRC)))
print("copied:", copied)
print("production-only files kept:", extra)
