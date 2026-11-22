#!/usr/bin/env python3
"""Carve Intel VBT images ($VBT ...) out of a firmware image. Usage: vbt_extract.py <fw.bin> <outdir>"""
import struct, sys, pathlib
data = pathlib.Path(sys.argv[1]).read_bytes(); out = pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
off = 0; n = 0
while (off := data.find(b"$VBT", off)) >= 0:
    sig = data[off:off+20].split(b"\0")[0].decode("ascii", "replace")
    ver, hdr, size = struct.unpack_from("<HHH", data, off + 0x14)
    blob = data[off:off+size]
    p = out / f"vbt{n}_{off:#x}.bin"; p.write_bytes(blob)
    print(f"{off:#010x} sig={sig!r} ver={ver} hdr={hdr} size={size} -> {p.name}")
    off += 4; n += 1
