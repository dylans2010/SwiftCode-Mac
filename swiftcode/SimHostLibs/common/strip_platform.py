#!/usr/bin/env python3

import struct
import sys

PLATFORM_CMDS = {0x32, 0x24, 0x25, 0x2F, 0x30}

def strip(path):
    with open(path, "rb") as f:
        data = bytearray(f.read())
    magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from("<IiiIIIII", data, 0)
    if magic != 0xFEEDFACF or filetype != 1:
        sys.exit("strip_platform.py: %s is not a 64-bit Mach-O object" % path)
    off, kept, removed = 32, [], 0
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        if size < 8 or off + size > 32 + sizeofcmds:
            sys.exit("strip_platform.py: %s: malformed load commands" % path)
        if cmd in PLATFORM_CMDS:
            removed += 1
        else:
            kept.append(bytes(data[off:off + size]))
        off += size
    if removed == 0:
        return
    blob = b"".join(kept)
    data[32:32 + sizeofcmds] = blob + bytes(sizeofcmds - len(blob))
    struct.pack_into("<IiiIIIII", data, 0, magic, cputype, cpusub, filetype, len(kept), len(blob), flags, reserved)
    with open(path, "wb") as f:
        f.write(data)

for p in sys.argv[1:]:
    strip(p)
