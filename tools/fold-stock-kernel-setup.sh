#!/bin/sh
# Bring up ISH / ECLite / keyboard-dock on an *unpatched* distro kernel, at runtime.
#
#   sudo tools/fold-stock-kernel-setup.sh <path-to-patched-ishtp_eclite.c>
#
# - binds intel_ish_ipc to the Lakefield ISH (8086:98fc) via new_id
# - builds the patched intel_ishtp_eclite and lenovo-fold-dock against the
#   running kernel's headers and swaps them in
# - re-probes the ACPI battery (it gave up before ECLite was available)
#
# Requires: kernel headers for `uname -r`, gcc, make. Not persistent across reboot.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
ECLITE_SRC=${1:?patched ishtp_eclite.c (e.g. from a patched tree)}
KDIR=/lib/modules/$(uname -r)/build
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "== ISH"
modprobe intel_ish_ipc
if [ ! -e /sys/bus/pci/devices/0000:00:12.0/driver ]; then
	echo "8086 98fc" > /sys/bus/pci/drivers/intel_ish_ipc/new_id || true
fi
for i in $(seq 1 20); do
	ls /sys/bus/ishtp/devices/ 2>/dev/null | grep -qi 6a19cc4b && break
	sleep 0.5
done

echo "== ECLite"
mkdir -p "$WORK/eclite"
cp "$ECLITE_SRC" "$WORK/eclite/ishtp_eclite.c"
printf 'obj-m := intel_ishtp_eclite.o\nintel_ishtp_eclite-y := ishtp_eclite.o\n' > "$WORK/eclite/Kbuild"
make -s -C "$KDIR" M="$WORK/eclite" modules
rmmod intel_ishtp_eclite 2>/dev/null || true
insmod "$WORK/eclite/intel_ishtp_eclite.ko"
sleep 2

echo "== Battery re-probe"
for b in /sys/bus/acpi/devices/PNP0C0A:*; do
	n=$(basename "$b")
	[ "$(cat "$b/status")" = 0 ] && continue
	echo "$n" > /sys/bus/platform/drivers/acpi-battery/unbind 2>/dev/null || true
	echo "$n" > /sys/bus/platform/drivers/acpi-battery/bind 2>/dev/null || true
done

echo "== Keyboard dock"
cp -r "$HERE/drivers/lenovo-fold-dock" "$WORK/dock"
make -s -C "$KDIR" M="$WORK/dock" modules
rmmod lenovo_fold_dock 2>/dev/null || true
insmod "$WORK/dock/lenovo-fold-dock.ko"

echo "== Result"
ls /sys/class/power_supply/
d=/sys/bus/platform/devices/LEN009E:00
echo "keyboard_docked=$(cat $d/keyboard_docked) occlusion=$(cat $d/occlusion)"
