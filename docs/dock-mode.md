# Keyboard-docked mode and rotation

Policy (as requested): **docked** → fixed 1536×1006 layout above the keyboard, accelerometer
ignored; **not docked** → full panel, rotation follows the accelerometer.

## Kernel
- `lenovo-fold-dock` (LEN009E): `keyboard_docked` (sysfs_notify + KOBJ_CHANGE), `occlusion`.
- Patch 0023 (i915/dsi): mode **1536x1006@60.02** on DSI-1 (panel timings, shorter active area),
  scanned out 1:1 by the pipe scaler against the logical top edge — the raw bottom, since the
  panel is mounted upside down (pfit window y = 2048 − 1006 = 1042). Area under the keyboard is
  dark. Explicit FULLSCREEN scaling still stretches. Verified: correct placement, no flicker.

## Touch mapping
The digitizer reports in an **upright** frame; KWin rotates touch by the output transform, and the
output is `inverted` (panel mount). Hence the udev baseline `-1 0 1 0 -1 1` (cancels KWin's flip).
KWin's per-device `calibrationMatrix` (D-Bus `org.kde.KWin.InputDevice`, row-major 4×4, entries
(0,2)/(1,2) are translations) is applied *before* KWin's output-transform flip:
- full panel: `-1,0,1, 0,-1,1`
- docked: `-1,0,1, 0,-k,1` with k = **1.98** (calibrated; geometric 2048/1006 = 2.036 was slightly
  low-biased — the digitizer active area is ~3 % taller than the panel's visible area).
  First attempt `0,-k,k` put all touches outside the output (measured with
  `libinput debug-events --set-calibration`).

## Accelerometer → rotation (accel_3d, m/s², flat-unfolded panel)
| Position | Reading | kscreen rotation |
|---|---|---|
| portrait upright | y ≈ −8 | inverted |
| landscape 90° CW | x ≈ +9 | right |
| portrait upside down | y ≈ +9.7 | none |
| landscape 90° CCW | x ≈ −9.7 | left |
Threshold 6.5 m/s² on the dominant axis, two consecutive 0.5 s samples. iio-sensor-proxy is not
used (its sensor claim is polkit-gated to the active session; reading sysfs avoids that, and KWin's
own auto-rotation stays off so there is a single owner of rotation).

## Helper (`userspace/helper/`)
`thinkpad-fold-helper` (Python, stdlib only) + autostart entry. Install:
`/usr/local/bin/thinkpad-fold-helper`, `/etc/xdg/autostart/thinkpad-fold-helper.desktop`.
Env overrides: `FOLD_DOCKED_SCALE` (default 1.5), `FOLD_DOCKED_TOUCH_YSCALE` (1.98).
Uses `kscreen-doctor` (mode/scale/rotation) and `busctl` (KWin touch calibration). Restores the
pre-dock scale on undock. A manual Plasma rotation while docked gives a rotated partial display
(no corruption); the helper re-asserts on the next dock change.
Verified 2026-11-22: rotation in all four orientations, touch correct in rotated orientations,
dock/undock switching.
