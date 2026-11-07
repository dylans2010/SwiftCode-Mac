#!/usr/bin/env python3
import os
import statistics
import subprocess
import sys

out = sys.argv[1]
runs = int(sys.argv[2]) if len(sys.argv) > 2 else 3
simd_file = sys.argv[3] if len(sys.argv) > 3 else None

def run(variant):
    args = [os.path.join(out, f"bench-{variant}"), out, variant]
    text = subprocess.run(args, capture_output=True, text=True, check=True).stdout
    return parse(text)

def parse(text):
    r = {}
    for line in text.splitlines():
        if line.startswith("#") or "\t" not in line:
            continue
        name, ns, _ops = line.split("\t")
        r[name] = float(ns)
    return r

results = {"apple": [], "swiftcode": []}
for v in ("apple", "swiftcode"):
    run(v)
for _ in range(runs):
    for v in ("apple", "swiftcode"):
        results[v].append(run(v))
names = list(results["apple"][0].keys())
simd = parse(open(simd_file).read()) if simd_file else {}
head = "| Benchmark | Mac runtime (ns) | SwiftCode, Mac native (ns) | SwiftCode / Mac |"
sep = "|---|---:|---:|---:|"
if simd:
    head += " SwiftCode on arm64 Linux, swiftcode-simd (ns) |"
    sep += "---:|"
print(head)
print(sep)
for n in names:
    a = statistics.median(r[n] for r in results["apple"])
    y = statistics.median(r[n] for r in results["swiftcode"])
    row = f"| {n} | {a:.2f} | {y:.2f} | {y / a:.2f} |"
    if simd:
        row += f" {simd.get(n, float('nan')):.2f} |"
    print(row)
