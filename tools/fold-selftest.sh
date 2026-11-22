#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Hardware self-test for Linux on the ThinkPad X1 Fold Gen 1: run after installing a new kernel /
# package version, from a logged-in desktop session (some checks use the session's D-Bus).
#
#   sudo x1fold-selftest (packaged) or sudo tools/fold-selftest.sh   # automatic checks
#   sudo tools/fold-selftest.sh --suspend  # also one 20 s s2idle cycle (rtcwake)
#
# Prints PASS/WARN/FAIL per check and a summary; exits non-zero on any FAIL. Checks that need a
# person (picture on the external monitor, keyboard wake, sound) are listed at the end.
set -uo pipefail

SUSPEND=0
[[ ${1:-} = --suspend ]] && SUSPEND=1
[[ $EUID -eq 0 ]] || { echo "run as root (sudo)"; exit 2; }

pass=0 warn=0 fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; pass=$((pass + 1)); }
soft() { printf '  \033[33mWARN\033[0m %s\n' "$*"; warn=$((warn + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail + 1)); }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
check() { # check "description" command... -> PASS if the command succeeds
	local d=$1; shift
	if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}
klog() { journalctl -k -b --no-pager -o cat 2>/dev/null; }

hdr "System"
printf '  %s, kernel %s, BIOS %s\n' "$(cat /sys/class/dmi/id/product_family 2>/dev/null)" \
	"$(uname -r)" "$(cat /sys/class/dmi/id/bios_version 2>/dev/null)"
[[ $(cat /sys/class/dmi/id/product_family 2>/dev/null) = "ThinkPad X1 Fold Gen 1" ]] &&
	ok "machine is a ThinkPad X1 Fold Gen 1" || soft "not a ThinkPad X1 Fold Gen 1"
n=$(klog | grep -c -E "Oops|BUG:|kernel BUG|general protection|Call Trace:")
(( n == 0 )) && ok "no oops/BUG/call trace in this boot" || bad "$n oops/BUG/call-trace lines in the kernel log"
n=$(klog | grep -c -E "WARNING: CPU:")
(( n == 0 )) && ok "no kernel WARNINGs" || soft "$n kernel WARNING(s) (see journalctl -k)"
n=$(klog | grep -c -i "unclaimed")
(( n == 0 )) && ok "no unclaimed MMIO" || soft "$n unclaimed MMIO report(s)"
failed=$(systemctl --failed --no-legend | wc -l)
(( failed == 0 )) && ok "no failed systemd units" || soft "$failed failed systemd unit(s)"

hdr "Display (i915)"
check "i915 bound to 8086:9840" test "$(basename "$(readlink -f /sys/bus/pci/devices/0000:00:02.0/driver 2>/dev/null)")" = i915
c=$(ls -d /sys/class/drm/card*-DSI-1 2>/dev/null | head -1)
[[ -n $c && $(cat "$c/status") = connected ]] && ok "internal panel DSI-1 connected" || bad "DSI-1 not connected"
[[ -n $c && $(cat "$c/enabled") = enabled ]] && ok "DSI-1 enabled" || soft "DSI-1 not enabled (screen off?)"
check "backlight device" test -d /sys/class/backlight/intel_backlight
check "docked mode 1536x1006 offered" grep -qx 1536x1006 "$c/modes"
for p in DP-1 DP-2; do
	d=$(ls -d /sys/class/drm/card*-"$p" 2>/dev/null | head -1)
	[[ -n $d ]] && ok "USB-C display connector $p present ($(cat "$d/status"))" || bad "USB-C display connector $p missing (i915.lkf_tc?)"
done
klog | grep -q "PLL .* not locked" && bad "a display PLL failed to lock" || ok "no PLL lock failures"
klog | grep -q "HW state changed unexpectedly" && soft "combo PHY state warning" || ok "no combo PHY state warning"

hdr "GPU acceleration"
if command -v vainfo >/dev/null; then
	vainfo --display drm --device /dev/dri/renderD128 2>/dev/null | grep -q "VAProfileH264" &&
		ok "VA-API decoder available" || bad "VA-API not working (intel-media-driver / lkf_chipset_id)"
else
	soft "vainfo not installed (libva-utils): VA-API not checked"
fi
[[ $(cat /sys/bus/pci/devices/0000:00:02.0/device) = 0x4e71 ]] &&
	ok "Mesa GPU ID workaround active" || soft "Mesa GPU ID workaround not active (thinkpad-x1-fold-gpu-id.service)"

hdr "ISH / ECLite / sensors"
check "ISH bound (intel_ish_ipc)" test -n "$(ls -d /sys/bus/pci/drivers/intel_ish_ipc/0000:* 2>/dev/null)"
check "ECLite driver loaded" grep -q "^intel_ishtp_eclite " /proc/modules
bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
[[ -n $bat ]] && ok "battery $(basename "$bat"): $(cat "$bat/capacity")% $(cat "$bat/status")" || bad "no battery"
check "lid switch" test -n "$(grep -l 'Lid Switch' /sys/class/input/*/name 2>/dev/null)"
for s in accel_3d gyro_3d hinge; do
	grep -qx "$s" /sys/bus/iio/devices/iio:device*/name 2>/dev/null && ok "IIO sensor $s" || bad "IIO sensor $s missing"
done
dock=/sys/bus/platform/devices/LEN009E:00/keyboard_docked
[[ -r $dock ]] && ok "keyboard dock driver (docked=$(cat $dock))" || bad "lenovo-fold-dock missing ($dock)"

hdr "Touch"
check "ithc loaded" grep -q "^ithc " /proc/modules
check "touch input device" test -n "$(grep -l -i 'Touch Host Controller' /sys/class/input/*/name 2>/dev/null)"

hdr "Audio"
cards=$(cat /proc/asound/cards 2>/dev/null)
grep -q "AVS HD-Audio" <<<"$cards" && ok "speakers card (AVS HD-Audio)" || bad "no AVS HD-Audio card (SST firmware? dsp_driver=4?)"
grep -q -E "\[DMIC" <<<"$cards" && ok "microphone card (DMIC)" || bad "no DMIC card"
grep -q "AVS HDMI" <<<"$cards" && ok "display audio card (AVS HDMI)" || soft "no display audio card"
klog | grep -q "basefw load failed\|firmware boot failed" && bad "AVS firmware boot failed" || ok "AVS firmware booted"
dc=$(grep -l "^DMIC$" /sys/class/sound/card*/id 2>/dev/null | head -1)
if [[ -n $dc ]]; then
	n=$(basename "$(dirname "$dc")"); n=${n#card}
	v=$(amixer -c "$n" cget name='DMIC Volume' 2>/dev/null | sed -n 's/.*: values=//p')
	[[ $v = 2147483647* ]] && ok "DMIC gain at 0 dB" || soft "DMIC Volume is '$v' (udev rule 62?)"
fi

hdr "Wi-Fi / Bluetooth"
check "Wi-Fi interface" test -n "$(ls -d /sys/class/net/*/wireless 2>/dev/null)"
check "Bluetooth hci0" test -e /sys/class/bluetooth/hci0
klog | grep -q "hci0: Setup complete" && ok "Bluetooth firmware loaded" || bad "Bluetooth setup did not complete"
n=$(klog | grep -c "resetting the controller\|resetting it (")
(( n == 0 )) && ok "Bluetooth came up on the first try" || soft "Bluetooth needed $n setup retr(y/ies)"
[[ $(cat /sys/bus/serial/devices/serial0-0/power/wakeup 2>/dev/null) = enabled ]] &&
	ok "Bluetooth is a wakeup source" || bad "Bluetooth wakeup not enabled"
command -v bluetoothctl >/dev/null && bluetoothctl show 2>/dev/null | grep -q "Powered: yes" &&
	ok "Bluetooth powered" || soft "Bluetooth not powered (or bluetoothctl missing)"

if (( SUSPEND )); then
	hdr "Suspend (20 s s2idle, woken by the RTC)"
	before=$(date +%s)
	rtcwake -m freeze -s 20 >/dev/null 2>&1
	sleep 8   # let the drivers settle
	since=$(date -d "@$before" '+%Y-%m-%d %H:%M:%S')
	log=$(journalctl -k --since "$since" --no-pager -o cat)
	grep -q "PM: suspend exit" <<<"$log" && ok "suspend/resume cycle" || bad "no 'PM: suspend exit'"
	grep -q -E "Oops|BUG:|Call Trace:" <<<"$log" && bad "oops/trace during suspend" || ok "no oops during suspend"
	grep -q "hci0: Suspended" <<<"$log" && ok "Bluetooth LPM suspend" || soft "no Bluetooth LPM suspend"
	grep -q -E "Unknown HCI Command|Frame reassembly failed" <<<"$log" && bad "Bluetooth errors after resume" || ok "Bluetooth clean after resume"
	[[ $(cat "$c/status" 2>/dev/null) = connected ]] && ok "panel still connected" || bad "panel lost after resume"
	f=/sys/kernel/debug/pmc_core/slp_s0_residency_usec
	[[ -r $f ]] && soft "S0ix residency counter: $(cat $f) us (informational)"
fi

hdr "Manual checks (not automated)"
cat <<'EOF'
  - picture right side up, brightness keys / slider change the backlight
  - keyboard docked on the screen -> docked mode; removed -> full panel, rotation follows the tablet
  - touch lands under the finger in both modes
  - speakers play, microphones record (Settings -> Sound)
  - external monitor via USB-C: picture, hot-unplug/replug, sound on "External Display"
  - sleep from the menu, a keypress on the Fold keyboard wakes it, typing works immediately
EOF

printf '\n\033[1mSummary:\033[0m %d pass, %d warn, %d fail\n' "$pass" "$warn" "$fail"
(( fail == 0 ))
