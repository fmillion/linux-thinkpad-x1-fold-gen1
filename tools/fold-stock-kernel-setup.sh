#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Bring up ISH / ECLite / keyboard-dock on an *unpatched* distro kernel, at runtime.
#
#   sudo tools/fold-stock-kernel-setup.sh <kernel-tree-with-patches/6.18.64-applied>
#
# - builds the patched intel-ish-ipc (Lakefield ID + upstream reset-flow
#   backports, required on 6.18), intel_ishtp_eclite and lenovo-fold-dock
#   against the running kernel's headers and swaps them in
# - re-probes the ACPI battery (it gave up before ECLite was available)
#
# Requires: kernel headers for `uname -r`, gcc, make. Not persistent across reboot.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
TREE=${1:?path to a kernel tree with patches/6.18.64 applied}
KDIR=/lib/modules/$(uname -r)/build
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "== ISH"
mkdir -p "$WORK/ish"
cp -r "$TREE/drivers/hid/intel-ish-hid/ipc" "$TREE/drivers/hid/intel-ish-hid/ishtp" "$WORK/ish/"
printf 'obj-m := intel-ish-ipc.o\nintel-ish-ipc-objs := ipc/ipc.o ipc/pci-ish.o\nccflags-y += -I$(src)/ishtp\n' > "$WORK/ish/Kbuild"
make -s -C "$KDIR" M="$WORK/ish" modules
modprobe intel_ishtp
rmmod intel_ishtp_eclite intel_ishtp_hid intel_ish_ipc 2>/dev/null || true
insmod "$WORK/ish/intel-ish-ipc.ko"
for i in $(seq 1 20); do
	ls /sys/bus/ishtp/devices/ 2>/dev/null | grep -qi 6a19cc4b && break
	sleep 0.5
done

echo "== ECLite"
mkdir -p "$WORK/eclite"
cp "$TREE/drivers/platform/x86/intel/ishtp_eclite.c" "$WORK/eclite/ishtp_eclite.c"
printf 'obj-m := intel_ishtp_eclite.o\nintel_ishtp_eclite-y := ishtp_eclite.o\n' > "$WORK/eclite/Kbuild"
make -s -C "$KDIR" M="$WORK/eclite" modules
rmmod intel_ishtp_eclite 2>/dev/null || true
insmod "$WORK/eclite/intel_ishtp_eclite.ko"
sleep 2

echo "== Battery re-probe"
for b in /sys/bus/acpi/devices/PNP0C0A:*; do
	n=$(basename "$b")
	[ "$(cat "$b/status")" = 0 ] && continue
	# 6.18: ACPI driver "battery"; newer kernels: platform driver "acpi-battery"
	for drv in /sys/bus/acpi/drivers/battery /sys/bus/platform/drivers/acpi-battery; do
		[ -d "$drv" ] || continue
		echo "$n" > "$drv/unbind" 2>/dev/null || true
		echo "$n" > "$drv/bind" 2>/dev/null || true
	done
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
