#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Read-only hardware characterization for the ThinkPad X1 Fold Gen 1 under Linux.
# Run as root. Writes everything into ./fold-collect-<timestamp>/ and tars it.
# Output contains ACPI tables (including MSDM = Windows license key) — do not publish it.
set -u
OUT="fold-collect-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"/acpi "$OUT"/hid "$OUT"/sys
cd "$OUT" || exit 1

run() { f="$1"; shift; { echo "\$ $*"; "$@"; } > "$f" 2>&1 || true; }

run uname.txt uname -a
run cmdline.txt cat /proc/cmdline
run dmesg.txt dmesg
run lspci.txt lspci -nnvvk
run lsusb.txt lsusb -v
run lsmod.txt lsmod
run dmi.txt sh -c 'for f in /sys/class/dmi/id/*; do [ -f "$f" ] && [ -r "$f" ] && echo "$(basename $f): $(cat $f 2>/dev/null)"; done'
run cpuinfo.txt cat /proc/cpuinfo
run iomem.txt cat /proc/iomem
run interrupts.txt cat /proc/interrupts

# ACPI: prefer acpidump, always also copy raw sysfs tables.
command -v acpidump >/dev/null && acpidump > acpi/acpidump.txt 2>&1
for t in /sys/firmware/acpi/tables/* /sys/firmware/acpi/tables/dynamic/*; do
  [ -f "$t" ] && cat "$t" > "acpi/$(basename "$t")$(echo "$t" | grep -q dynamic && echo .dyn)" 2>/dev/null
done
rm -f acpi/MSDM*   # Windows product key; never needed
run acpi/devices.txt sh -c 'for d in /sys/bus/acpi/devices/*; do printf "%s hid=%s path=%s status=%s driver=%s\n" "$(basename $d)" "$(cat $d/hid 2>/dev/null)" "$(cat $d/path 2>/dev/null)" "$(cat $d/status 2>/dev/null)" "$(basename "$(readlink $d/physical_node/driver 2>/dev/null)" 2>/dev/null)"; done'

# HID devices and report descriptors
for h in /sys/bus/hid/devices/*; do
  [ -e "$h" ] || continue
  n=$(basename "$h")
  cat "$h/report_descriptor" > "hid/$n.rdesc" 2>/dev/null
  { cat "$h/uevent"; echo "driver=$(basename "$(readlink $h/driver 2>/dev/null)")"; } > "hid/$n.uevent" 2>/dev/null
done
run hid/i2c-devices.txt sh -c 'for d in /sys/bus/i2c/devices/*; do echo "$(basename $d) name=$(cat $d/name 2>/dev/null) modalias=$(cat $d/modalias 2>/dev/null) driver=$(basename "$(readlink $d/driver 2>/dev/null)")"; done'

# Graphics / input / power / sound / sensors
run sys/drm.txt sh -c 'ls -l /sys/class/drm/ /sys/class/graphics/ /sys/class/backlight/ 2>&1; cat /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/name 2>&1'
run sys/input.txt cat /proc/bus/input/devices
run sys/power_supply.txt sh -c 'for p in /sys/class/power_supply/*; do echo "== $p"; cat $p/uevent; done'
run sys/sound.txt sh -c 'cat /proc/asound/cards; ls -l /sys/bus/hdaudio/devices/ 2>&1; for c in /proc/asound/card*/codec*; do echo "== $c"; cat $c; done'
run sys/iio.txt sh -c 'for d in /sys/bus/iio/devices/*; do echo "== $d $(cat $d/name 2>/dev/null)"; ls $d; done'
run sys/firmware-requests.txt sh -c 'dmesg | grep -i -e firmware -e "direct firmware"'
run sys/gpio.txt sh -c 'cat /sys/kernel/debug/gpio 2>&1 | head -300'
run sys/pci-unbound.txt sh -c 'for d in /sys/bus/pci/devices/*; do [ -e $d/driver ] || echo "$(basename $d) $(cat $d/vendor):$(cat $d/device) class=$(cat $d/class)"; done'

cd ..
tar czf "$OUT.tar.gz" "$OUT" && echo "Wrote $OUT.tar.gz"
