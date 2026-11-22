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

## Root cause found: LE Coded scanning (patch 0030)
Clean-boot A/B: 20 s LE scans see 1–2 devices with **zero RSSI updates** whether Wi-Fi is on or
off. BlueZ uses extended scanning on **LE 1M + LE Coded** simultaneously; with this CcP firmware
that starves the 1M scan. `btmgmt phy …` without `LECODEDRX/TX` → same scan: **10 devices, 30
advertising reports**, and the keyboard is found immediately. Patch 0030 sets
`HCI_QUIRK_BROKEN_LE_CODED` for hardware variant 0x14 (BlueZ then never uses Coded).
The earlier "Wi-Fi coexistence" result was coincidental (the post-wedge state confused tests).

## Pairing the Fold Mini Keyboard
- It rotates its static random address per pairing session (seen: `E4:12:04:53:B0:AA`,
  `DD:CA:48:94:C7:3C`); after bonding, BlueZ follows it by its IRK.
- **Passkey entry required** (keyboard types the code). Plasma's list does not show it (no Name AD
  until connected; it reports "Lenovo Fold Mini Keyboard" after connecting) and a pair request
  routed to Plasma's agent ended in `AuthenticationCanceled`. Working method: `bluetoothctl` with
  `agent KeyboardDisplay`, `pair <addr>`, show the passkey to the user (here via `notify-send`),
  type it on the keyboard + Enter; then `trust`, `connect`. Keyboard and touchpad work.
- Dual boot: Windows and Linux share the adapter address but hold different bond keys → pairing
  in one OS breaks the other unless the LTK/IRK are copied across (TODO if dual-boot is kept).

## Bluetooth dead after s2idle — root cause (2026-11-22)
Symptom: after resume `Frame reassembly failed (-84)`, then every HCI command fails with -56
(`EBADRQC` = HCI status 0x01 "Unknown HCI Command", e.g. 0x0c01 Set Event Mask, 0x2042 LE Set
Ext Scan Enable). The controller answers like its **bootloader**: it was reset during suspend.
`modprobe -r hci_uart; modprobe hci_uart` recovers it (probe pulses reset, full firmware download).

Cause, from ACPI:
- SSDT5 (`Lkf_Rvp1`): `\_SB.PCI0.UA01.BTH0._PS0 = BTRK(1)`, `_PS3 = BTRK(0)`; `BTRK` drives the
  BT kill GPIO `GBTK` (pad 183, gpio offset 194, = the driver's "reset" line).
- DSDT `BTH0`: `_S0W = 2`, no `_PS1/_PS2`, host wake = `GpioInt(ExclusiveAndWake)` `GBTI`.
- The serdev device `serial0-0` uses the ACPI PM domain. For s2idle Linux evaluates `_S0W` (only
  when the device may wake *and* has a wake IRQ registered), and when the returned D-state (D2) is
  not supported it **falls back to D3cold** (drivers/acpi/device_pm.c). Not wake-capable at all
  (current state) → D3 anyway. D3 → `_PS3` → kill line asserted → controller powered off.
- `hci_intel` has no PM handling on the serdev path (`intel_pm_ops`/LPM are platform-device only;
  `intel_set_power()` returns early for serdev), so it does not notice the reset.

## Fix: keep BT powered in s2idle, LPM, keyboard wake (patches 0037-0039)
- 0037 (ACPI): for s2idle, a device that may wake through a wake IRQ and whose `_S0W` state is
  not implemented now goes to the deepest implemented state above it (here D0) instead of
  D3cold → `_PS3` (kill line) is no longer run. Other devices keep the old fallback.
- 0038 (hci_intel serdev): host-wake from the ACPI resources (`acpi_dev_gpio_irq_get()`;
  `fwnode_irq_get()` only parses Interrupt resources) — here GpioInt pad 185, irq "bt-host-wake";
  device wakeup capable, wake IRQ registered (that also makes ACPI evaluate `_S0W`).
- 0039 (hci_intel serdev): Intel LPM for system sleep — suspend request `f1 01 01 01` acked
  ("Suspended"), controller holds data and wakes us via the host-wake GPIO; on resume the LPM
  wake packet (or resume-ack). The CcP sends no LPM "TX idle" notifications on this path, so the
  request is not gated on them. Setup retries Read Version after another reset pulse (the
  intermittent boot failure: stale bytes from the controller's boot put the H4 parser inside a
  packet).
- Verified: s2idle with the keyboard connected, untouched ≥ 1 min (power LED breathing), a
  keypress wakes the Fold in ~5 s, typing works immediately (no firmware reload).
- The wake arrives as IRQ 14 (the GPIO controller); the host-wake handler itself is not replayed
  after resume (count stays 0) — harmless, resume sends the LPM wake packet.
- Open: confirm the setup retry fixes the boot-time failure (it was intermittent: watch for
  "resetting it (1/2)" in dmesg).
- Patch 0042: the setup retry caught the boot-time failure (answer `04 0e 0d 20 05 fc 00 37 14 …`
  behind stale bytes `20 00 00 00 03`; one reset fixed it). A different, rarer failure — firmware
  download at 921600 timing out (`0xfc09 tx timeout`) — is now covered by resetting the controller
  and re-running the whole setup at 115200. Resume no longer forces flow control off (the LPM
  helpers restore the operational state: flow control on).

## Pairing in Plasma works (since the LE Coded fix)
On a fresh install with the packages (2026-11-22), Plasma's Bluetooth settings list
"Lenovo Fold Mini Keyboard" and pair it, including the PIN typed on the keyboard. The earlier
failure (not listed; `AuthenticationCanceled`) came before patch 0030: with LE Coded scanning the
keyboard was barely seen at all. `bluetoothctl` remains the fallback without Plasma.
