# Roadmap

Ordering is by dependency, not by how visible the feature is. Several user-facing goals
(battery, keyboard dock, lid, sensors/rotation) all sit on **ISH + ECLite**, and everything
graphical sits on **i915 Lakefield + DSI**.

## Phase 0 — Characterize under Linux (needs Linux booted on the Fold, with SSH)
- `acpidump` (full SSDT set; `\_SB.DEVD` with `GDST`/`GDSZ`/`NSMC` is in an SSDT we can't get from Windows).
- `lspci -nnvv`, `lsusb -v`, `dmesg`, `/sys/bus/hid/devices/*/report_descriptor` (STME9100; ISH once bound).
- Confirm GPU on simpledrm/efifb; check GOP framebuffer orientation.

## Phase 1 — ISH + ECLite (keystone; small patches)
1. `intel-ish-hid`: add `8086:98FC` (LKF). Verify ISH FW is loaded by BIOS (no host FW load).
2. `intel_ishtp_eclite`: also match `INT3538` → serves ACPI OpRegions 0x9E/0x9F.
   Expected wins: battery + AC (ACPI `BAT0`/`ADP`), `LID0`, `\_SB.DEVD.DOST` updates, thermals.
3. Sensors: `hid-sensor-hub` → IIO accel/gyro ×2; identify remaining custom sensors.

## Phase 2 — Dock / posture
1. `lenovo-fold-dock` platform driver for `LEN009E`: notify handler → `GDST`, `GDSZ`;
   input device with `SW_DOCK` (or `SW_TABLET_MODE` inverted, TBD), sysfs `docked` + `occlusion`.
2. Optional: HKEY `LEN026A` support in thinkpad_acpi (no-EC mode) for DYTC/platform_profile + hotkeys.
3. iio-sensor-proxy: pick the correct IMU for rotation (mount matrix via hwdb).

## Phase 3 — Display (largest) — DONE except docked mode (see docs/dsi-bringup.md)
1. i915: Lakefield platform enablement (Gen11/ICL-derived display, EHL/JSL-like render),
   based on the Galaxy Book S LKF series; DSI port A with VBT sequences (SN65DSI86 programmed
   by VBT generic writes).
2. Backlight via display-engine PWM (controller 0, 990 Hz).
3. Docked mode: expose 1536×1006 (VBT OEM mode block 20), top-aligned via pipe scaler.
4. Mesa: iris PCI ID for 0x9840 (if not already present).
5. Characterize flicker: LACE/ALS (VBT-enabled), FBC, PSR (n/a for DSI video mode), DC states.

## Phase 4 — Audio
AVS driver on `98C8` with LKF base FW, ALC287 (17aa:22c6) codec quirks, DMIC via NHLT, UCM.

## Phase 5 — The rest
BT (`hci_intel` serdev series), touch (`ithc` + patch 0022 — DONE, pen untested), S0ix (`intel_pmc_core`/`intel_idle` LKF),
KDE integration (dock → mode switch + rotation lock; undock → full panel + auto-rotate).
