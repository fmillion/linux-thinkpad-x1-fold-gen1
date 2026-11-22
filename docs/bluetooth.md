# Bluetooth (Intel CcP, ACPI INT33E4, H4 over LPSS UART)

- Controller: Intel "CcP" (hardware variant 0x14), described in ACPI as `INT33E4`, a **serdev**
  child of the LPSS UART `\_SB.PCI0.UA01` (ttyS5 / serial0). Mainline `hci_intel` (6.18) only
  handles the older LPSS-platform-device style (`INT33E1/INT33E3`) and has no variant 0x14.
- Patches 0024–0027: Cai Yu's series (bluez/bluetooth-next PR #821, patches 15–18, written for
  the ThinkPad X1 Fold Gen 1; not merged upstream as of 2026-11): LPM tty-only fixes, variant
  0x14, serdev support (`INT33E4`), firmware download at 921.6 kbaud. Patch 17 needed context
  fuzz on 6.18 (verified placement). Patch 0028: `serdev_device_set_drvdata()` missing in
  `intel_serdev_probe()` (found by the Galaxy Book S work) — without it RX is dropped.
- Firmware: `intel/ibt-20-1-3.sfi` + `.ddc` (linux-firmware-intel).
- Result (2026-11-22): bootloader rev 0.3 (2017-w24), FW 193-33.24 loaded in 12.1 s at 921600,
  "Setup complete"; BlueZ 5.88 controller `hci0` powered. A few "Frame reassembly failed (-84)"
  at start-up and "Malformed MSFT vendor event" are cosmetic.
- Userspace: `bluez`, `bluez-utils`, `bluetooth.service` enabled; Plasma bluedevil.
- Known from the Galaxy Book S: `modprobe -r hci_uart` and one shutdown hung once there (not seen
  here yet).
