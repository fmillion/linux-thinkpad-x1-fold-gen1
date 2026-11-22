# Prior art & references

Gathered 2026-11-22. "Gen 2" = ThinkPad X1 Fold 16 (2022, Alder Lake) — different platform,
listed only where mechanisms may carry over.

## ThinkPad X1 Fold Gen 1
- Lars Ingebrigtsen, "Linux on the Lenovo ThinkPad X1 Fold" (2021, updated 2026): boots; GPU on VESA;
  no touch/battery. https://lars.ingebrigtsen.no/2021/01/16/linux-on-the-lenovo-thinkpad-x1-fold/
- Lenovo forums thread (pen via ithc + `intremap=nosid`):
  https://forums.lenovo.com/t5/Other-Linux-Discussions/X1-Fold-OS-Linux-where-to-start-and-how-it%E2%80%99s-going/m-p/5120185
- `hci_intel` serdev + variant 0x14 series tested on 20RK (not merged):
  https://github.com/bluez/bluetooth-next/pull/821
- Windows-side notes / tuning: https://csdvrx.github.io/ , https://chise.hachiroku.com/kludge/x1f-tuning/
- Lenovo Mode Switcher download: https://support.lenovo.com/us/en/downloads/ds546903
- PSREF: https://psref.lenovo.com/syspool/Sys/PDF/ThinkPad/ThinkPad_X1_Fold_Gen_1/ThinkPad_X1_Fold_Gen_1_Spec.pdf

## Lakefield (same SoC) — Samsung Galaxy Book S
- https://github.com/franke7777/galaxy-book-s-linux — ISH `new_id`, eclite `INT3538`, i915 render-only
  (EHL profile) + simpledrm, BT fix, AVS audio, S0ix notes.
- https://github.com/Independent-Scientist/lakefield-kernel-fixes — i915 LKF display "impersonation"
  patch series (MIPI-DSI panel), `docs/i915.md`.
- Intel: "i915 support for LKF-based platforms has not been provided":
  https://www.mail-archive.com/intel-gfx@lists.freedesktop.org/msg335056.html

## Touch
- https://github.com/quo/ithc-linux (Intel THC; issue #5 re: IOMMU / `intremap=nosid`)

## Sensors
- `drivers/iio/position/hid-sensor-custom-intel-hinge.c`:
  https://lkml.kernel.org/lkml/20201203035352.13918-3-xiang.ye@intel.com/t/

## Gen 2 (X1 Fold 16) — mechanisms to compare
- thinkpad_acpi keyboard-on-screen (`\_SB.DEVD.GDST`, hkey 0x60c0, sysfs `keyboard_attached_on_screen`):
  https://ratatoskr.run/lkml/2026/08/17461194 , https://ratatoskr.run/platform-driver-x86/2026/04/3519234/t
- Half-blank userspace: https://github.com/pepperpepperpepper/x1fold (wlroots/sway patches, Wacom half latch),
  https://github.com/jeblair/x1fold (GNOME), https://github.com/4a-ge/ThinkPad-X1-Fold-16-Gen1-Gnome-Extension,
  https://github.com/dubhagen/omarchy-x1fold (Hyprland)

## KDE custom modes (Plasma 6.6+)
- libkscreen !266, kwin !8534: `kscreen-doctor output.eDP-1.addCustomMode.W.H.mHz.full|reduced`
  https://invent.kde.org/plasma/libkscreen/-/merge_requests/266
