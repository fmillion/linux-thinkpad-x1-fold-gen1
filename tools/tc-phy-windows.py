#!/usr/bin/env python3
# DO NOT RUN: hard-hung the Fold (unpowered TC PHY). See docs/external-display.md.
"""Dump the Type-C PHY register space 0x168000+tc*0x1000 under each HIP_INDEX window (0-3)
to tell a TGL Dekel PHY (windowed) from an ICL MG PHY (flat). Writes only HIP_INDEX
(0x1010a0, the PHY window selector) and restores it. usage: tc-phy-windows.py TC OUTDIR"""
import mmap, os, struct, sys
tc, outdir = int(sys.argv[1]), sys.argv[2]
fd = os.open("/sys/bus/pci/devices/0000:00:02.0/resource0", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 16 << 20, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
rd = lambda o: struct.unpack_from("<I", m, o)[0]
def wr(o, v): struct.pack_into("<I", m, o, v)
HIP = 0x1010a0 if tc < 4 else 0x1010a4
sh = (tc % 4) * 8
orig = rd(HIP)
base = 0x168000 + tc * 0x1000
try:
    for w in range(4):
        wr(HIP, (orig & ~(0xff << sh)) | (w << sh)); rd(HIP)
        with open(os.path.join(outdir, "tc%d-win%d.txt" % (tc, w)), "w") as f:
            for off in range(0, 0x1000, 4):
                f.write("0x%04x 0x%08x\n" % (off, rd(base + off)))
finally:
    wr(HIP, orig)
print("HIP_INDEX was 0x%08x, restored 0x%08x" % (orig, rd(HIP)))
