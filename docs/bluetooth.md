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

## Keyboard pairing investigation (2026-11-22)
- The Fold keyboard is BLE: static random address (here `E4:12:04:53:B0:AA`), appearance 0x03C1,
  HID UUID 0x1812, Swift Pair manufacturer data (0x0006) "Lenovo Fold", **no Name AD** → Plasma's
  pairing list does not show it (BlueZ only has the address as alias). Pair via `bluetoothctl`.
- LE scanning is unreliable: some 20–60 s scans hear only 1–4 devices with weak RSSI, one scan
  (Wi-Fi rfkill-blocked) heard ~15 incl. the keyboard at −53 dBm and the phone at −45 dBm; the next
  scan with Wi-Fi still blocked was deaf again → Wi-Fi coexistence is *not* the (only) cause.
- Controller wedges intermittently: `Unable to disable scanning: -110`, then all HCI commands time
  out; recoverable with `bluetoothctl power off/on`.
- Hypothesis: the operational link stays at **115200 baud** (serdev proto `oper_speed = 0`; the
  link drops back from the 921600 download speed), which a busy LE scan can saturate.
  Experiment (patch 0029, `hci_uart.intel_ccp_speed`): switching the *operational* firmware to
  921600 or 3000000 with Intel Set UART Baudrate (0xfc06) fails — host and controller end up at
  different rates (frame reassembly errors, HCI Reset timeout). Default left at 115200.
  Repeated rmmod/modprobe can leave the controller in an unknown state → test from a fresh boot.
- Also traced: i915 `Unclaimed write 0x64834` comes from `gen11_display_irq_reset()` during
  runtime suspend (an IRQ register of a display block LKF lacks) — harmless, loose end.
