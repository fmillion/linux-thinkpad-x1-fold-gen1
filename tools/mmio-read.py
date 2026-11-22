#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Read 32-bit i915 MMIO registers through the PCI BAR0 sysfs mapping (root).
usage: mmio-read.py [-d 0000:00:02.0] OFFSET[:COUNT] [name] ...   (hex offsets)"""
import mmap, os, struct, sys
args = sys.argv[1:]
dev = "0000:00:02.0"
if args[:1] == ["-d"]:
    dev, args = args[1], args[2:]
fd = os.open("/sys/bus/pci/devices/%s/resource0" % dev, os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 16 << 20, mmap.MAP_SHARED, mmap.PROT_READ)
for a in args:
    off, _, cnt = a.partition(":")
    off, cnt = int(off, 16), int(cnt or "1")
    for i in range(cnt):
        o = off + 4 * i
        print("0x%06x = 0x%08x" % (o, struct.unpack_from("<I", m, o)[0]))
