# Touchscreen (Intel THC 8086:98d0 + Wacom 056a:5102)

- Controller: Intel Touch Host Controller at 00:11.0 (class 0x0901). Not supported by the in-tree
  `intel-thc-hid` (MTL+). Driver: out-of-tree **ithc** (github.com/quo/ithc-linux, CC0/public
  domain), tested at commit `6d53c9c`; builds unmodified against 6.18.64
  (`tools/build-ithc.sh`). Legacy mode ("no ACPI config"); device = Wacom `056A:5102`; the
  in-kernel `wacom` HID driver binds and creates "…Finger" (INPUT_PROP_DIRECT, MT slots) and
  "…Pen". Standard HID — no iptsd needed.
- IRQ mode fails without a fix: report-descriptor reads time out (MSIs blocked by interrupt
  remapping source-id verification; no DMAR fault is logged). Polling (`ithc poll=1`) works.
  Fix: patch 0022 (iommu/vt-d: no SID verification for LKF THC 98d0/98d1 only) — instead of the
  system-wide `intremap=nosid`.
- Orientation: digitizer reports in the panel's native (upside-down) frame →
  `LIBINPUT_CALIBRATION_MATRIX=-1 0 1 0 -1 1` via `userspace/udev/60-thinkpad-x1-fold.rules`.
  **TODO when doing auto-rotation / docked mode:** verify KWin applies the output transform to
  touch on top of this (calibration fixes only the physical mount).
- Verified (polling mode, 2026-11-22): tap, drag, one-finger scroll, pinch-zoom. Pen untested
  (no pen available).
- **With patch 0022: IRQ mode works** — ithc autoloads, `IR-PCI-MSI-0000:00:11.0` interrupt
  counting, same touch behaviour, no warnings. No `ithc` module options needed.
