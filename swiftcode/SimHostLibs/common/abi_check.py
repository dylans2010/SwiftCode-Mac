#!/usr/bin/env python3

import argparse
import os
import re
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))

def run(cmd):
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    if p.returncode != 0:
        sys.exit("abi_check.py: %s failed:\n%s" % (cmd[0], p.stderr))
    return p.stdout

def functions(disasm):
    funcs, cur = {}, None
    for line in disasm.splitlines():
        m = re.match(r"^(_\w+):$", line)
        if m:
            cur = m.group(1)
            funcs[cur] = []
        elif cur and re.match(r"^\s+[0-9a-f]+:", line):
            insn = line.split(":", 1)[1].split(";", 1)[0]
            funcs[cur].append(" ".join(insn.replace("\t", " ").split()))
    return funcs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clang", required=True)
    ap.add_argument("--ld", required=True)
    ap.add_argument("--objdump", required=True)
    ap.add_argument("--python", default=sys.executable)
    ap.add_argument("--out", required=True)
    ap.add_argument("cflags", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cflags = [f for f in a.cflags if f != "--"]
    os.makedirs(a.out, exist_ok=True)
    objs = []
    for name in ("callee", "caller"):
        o = os.path.join(a.out, name + ".o")
        run([a.clang] + cflags + ["-c", "-o", o, os.path.join(here, "abi_check", name + ".c")])
        objs.append(o)
    run([a.python, "-I", os.path.join(here, "strip_platform.py")] + objs)
    dylib = os.path.join(a.out, "abi_probe.dylib")
    run([a.ld, "-arch", "arm64", "-platform_version", "ios-simulator", "27.0", "27.1", "-dylib",
         "-install_name", "/swiftcode/abi_probe.dylib", "-no_adhoc_codesign", "-o", dylib] + objs)
    f = functions(run([a.objdump, "-d", "--macho", "--no-show-raw-insn", dylib]))
    errors = []

    def need(fn):
        if fn not in f:
            errors.append("function %s missing from the disassembly" % fn)
            return []
        return f[fn]

    callee = need("_yc_abi_variadic")
    if any(re.search(r"\b(x[1-7]|q[0-7])\b", i) for i in callee if re.match(r"st", i)):
        errors.append("variadic callee spills argument registers (AAPCS64 va_start): %s" % callee)
    caller = need("_yc_abi_call_variadic")
    pre = caller[:next((k for k, i in enumerate(caller) if i.startswith("bl")), len(caller))]
    if any(re.match(r"mov [wx][12],", i) for i in pre):
        errors.append("variadic caller passes anonymous arguments in registers: %s" % pre)
    if not any(re.match(r"st(r|p)\b.*\[sp", i) for i in pre):
        errors.append("variadic caller does not store anonymous arguments to the stack: %s" % pre)
    many = need("_yc_abi_many")
    if not any(re.match(r"ldrs?b\s+\w+, \[sp\]", i) for i in many) or \
            not any(re.match(r"ldrs?h\s+\w+, \[sp, #0x2\]", i) for i in many):
        errors.append("10-argument callee does not read char at [sp] and short at [sp, #2]: %s" % many)
    cm = need("_yc_abi_call_many")
    if not any(re.match(r"strb\s+\w+, \[sp\]", i) for i in cm) or \
            not any(re.match(r"strh\s+\w+, \[sp, #0x2\]", i) for i in cm):
        if not any(re.match(r"str\s+w\w+, \[sp\]", i) for i in cm) or any("[sp, #0x8]" in i for i in cm):
            errors.append("10-argument caller does not pack char/short at [sp]/[sp, #2]: %s" % cm)
    if errors:
        for e in errors:
            sys.stderr.write("abi_check.py: FAIL: %s\n" % e)
        sys.exit(1)
    print("abi_check: DarwinPCS ok (variadic args on the stack, stack args packed at natural size)")

if __name__ == "__main__":
    main()
