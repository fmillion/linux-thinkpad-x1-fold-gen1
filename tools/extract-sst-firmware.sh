#!/bin/sh
# Install the Lakefield Intel SST (AVS) DSP base firmware from this machine's own Windows install.
#   sudo tools/extract-sst-firmware.sh /path/to/mounted/Windows   (e.g. mounted read-only)
# Picks the newest intcoed driver package's Fw/dsp_fw_release.bin with FW version >= 10.28.0.5646
# (AVS minimum). Tested: 10.28.0.5995 (driver 10.28.0.6539) on the ThinkPad X1 Fold Gen 1.
# The firmware is Intel's; it is not redistributed by this project.
set -eu
WIN=${1:?mounted Windows root}
DEST=/usr/lib/firmware/updates/intel/avs/lkf/dsp_basefw.bin
best=; bestver=0
for f in "$WIN"/Windows/System32/DriverStore/FileRepository/intcoed.inf_amd64_*/Fw/dsp_fw_release.bin; do
	[ -f "$f" ] || continue
	v=$(python3 -I - "$f" <<'PY'
import struct, sys
b = open(sys.argv[1], "rb").read(); i = b.find(b"$MN2")
print("%d" % (struct.unpack_from("<HHHH", b, i + 8)[3] if i >= 0 and b[:4] == b"$AE1" else 0))
PY
)
	echo "$f: build $v"
	if [ "$v" -gt "$bestver" ]; then best=$f; bestver=$v; fi
done
[ -n "$best" ] || { echo "no SST firmware found"; exit 1; }
[ "$bestver" -ge 5646 ] || { echo "newest firmware (build $bestver) is older than 10.28.0.5646"; exit 1; }
install -Dm644 "$best" "$DEST"
echo "installed $best (10.28.0.$bestver) -> $DEST"
