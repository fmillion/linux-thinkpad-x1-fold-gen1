# Linux on the Lenovo ThinkPad X1 Fold Gen 1

Kernel patches, packages and userspace configuration that make Linux a
fully usable daily system on the **ThinkPad X1 Fold Gen 1** (2020, machine types 20RK/20RL,
Intel Lakefield i5-L16G7) — including the foldable OLED panel, the magnetic Bluetooth keyboard
dock, touch, audio and USB-C external displays.

Lakefield never got display, audio-DSP or Type-C support in mainline Linux, so most of this
project is reverse engineering: the BIOS's own graphics driver (GOP), the VBT, the ACPI tables
and register state, documented in [`docs/`](docs/).

- **Kernel:** Linux **6.18.64 LTS**, as a patch series against the pristine release
  ([`patches/6.18.64/`](patches/6.18.64/), 43 patches, including the keyboard-dock driver)
- **Packages:** Arch Linux PKGBUILDs and an installer ([`packaging/`](packaging/), [`install.sh`](install.sh))
- **Userspace:** udev, PipeWire/WirePlumber, SDDM and a Plasma helper ([`userspace/`](userspace/))
- **Tested on:** 20RK000LUS, BIOS N2PET64W (1.36), Arch Linux, KDE Plasma 6 (Wayland)

## Status

| Feature | State | Notes |
|---|---|---|
| Internal panel (DSI → SN65DSI86 → eDP OLED, 1536×2048) | ✅ | i915 drives it natively; orientation quirk; PWM brightness |
| GPU acceleration (GLES, VA-API video decode) | ✅ | Mesa/intel-media-driver need an ID workaround until they know `0x9840` |
| Keyboard docked on the screen (1536×1006 mode) | ✅ | Docked mode, fixed orientation, touch mapped to the visible area |
| Screen rotation (accelerometer) | ✅ | Helper follows the accelerometer when undocked |
| Touch | ✅ | Intel THC via out-of-tree [ithc](https://github.com/quo/ithc-linux) |
| Pen | ❔ | Untested |
| Speakers, microphones | ✅ | AVS driver; needs Intel's SST firmware from the Windows driver package |
| USB-C external display (DP alt mode) + display audio | ✅ | Hot-plug, extend/mirror, suspend tested at 1080p on port 1 |
| Wi-Fi | ✅ | Stock `iwlwifi` |
| Bluetooth, Fold Mini Keyboard | ✅ | Keyboard and touchpad; survives suspend; **a keypress wakes the Fold** |
| Battery, AC, lid, dock state (ISH + ECLite) | ✅ | |
| Suspend (s2idle) | ✅ | Display, Bluetooth and external display all resume |
| Camera | ❔ | Enumerates as a UVC device; not tested further |
| USB-C port 2, higher DP link rates, docks | ❔ | Should work; not yet tested |

✅ works · ❔ untested

## How it works (short version)

- **ISH + ECLite:** the embedded-controller functions (battery, lid, dock) run on the Integrated
  Sensor Hub; patches add the Lakefield IDs and fix ISH bring-up on 6.18.
- **Display:** i915 runs Lakefield as an Elkhart Lake relative with its own descriptor. The panel
  needs the firmware's MIPI D-PHY (MCD) state preserved, DC9-only power management and a PCH-less
  panel power sequencer. See [`docs/dsi-bringup.md`](docs/dsi-bringup.md).
- **USB-C DisplayPort:** Lakefield's Type-C display path is a hybrid that no other Intel platform
  shares — Ice Lake FIA/hot-plug/clocking, a Tiger Lake Dekel PHY whose PLL uses Ice Lake's MG
  register layout, and a Tiger Lake transcoder interface — worked out from the Lakefield GOP.
  See [`docs/external-display.md`](docs/external-display.md).
- **Bluetooth:** the Intel CcP controller on a UART (serdev); the ACPI `_PS3` cuts its power in
  s2idle, so the fix keeps it powered and uses Intel's LPM protocol and the host-wake GPIO.
  See [`docs/bluetooth.md`](docs/bluetooth.md).
- **Dock mode:** `lenovo-fold-dock` exposes the keyboard-dock state from ACPI; the helper switches
  between the full panel and the docked mode. See [`docs/dock-mode.md`](docs/dock-mode.md).

## Installation (Arch Linux)

On a freshly installed Arch Linux on the Fold, with a USB keyboard and a network connection:

```sh
curl -fsSL https://raw.githubusercontent.com/fmillion/linux-thinkpad-x1-fold-gen1/main/install.sh | sudo bash
```

The installer builds and installs the packages, makes the patched kernel the default boot entry
and explains how to pair the keyboard after the reboot. Without a binary repository it builds the
kernel from source, which takes hours on the Fold itself. See [`packaging/README.md`](packaging/README.md)
for the packages and the options, and [`docs/install-checklist.md`](docs/install-checklist.md) for
a manual installation.

| Package | Contents |
|---|---|
| `x1fold` | Metapackage: everything below except the Plasma integration |
| `linux-x1fold`, `linux-x1fold-headers` | Linux 6.18.64 LTS (Arch's `linux-lts` config) with the patch series |
| `linux-x1fold-ithc` | Touch screen driver, built with the kernel |
| `x1fold-sst-firmware` | Intel audio DSP firmware, extracted from Lenovo's public driver package at build time |
| `x1fold-hwconfig` | udev, modprobe, PipeWire/WirePlumber configuration, GPU ID workaround |
| `x1fold-plasma` | KDE Plasma: keyboard-dock display mode, rotation, Wayland SDDM greeter |

Kernel parameters to rule things out when debugging: `i915.lkf_display=0` (panel on the firmware
framebuffer, GPU render-only), `i915.lkf_tc=0` (USB-C display ports off), `module_blacklist=i915`.

## Documentation

| Document | Contents |
|---|---|
| [`docs/findings.md`](docs/findings.md) | Hardware/firmware findings: ACPI, VBT, sensors, Windows behaviour |
| [`docs/dsi-bringup.md`](docs/dsi-bringup.md) | Internal panel bring-up in i915 |
| [`docs/external-display.md`](docs/external-display.md) | USB-C DP alt mode: register analysis, GOP findings, bring-up log |
| [`docs/audio.md`](docs/audio.md) | AVS audio, DMIC, display audio |
| [`docs/bluetooth.md`](docs/bluetooth.md) | CcP over serdev, LE Coded, pairing, suspend/wake |
| [`docs/dock-mode.md`](docs/dock-mode.md) | Keyboard-dock detection and docked display mode |
| [`docs/touch.md`](docs/touch.md) | Touch controller and calibration |
| [`packaging/README.md`](packaging/README.md) | Packages, installer, building |
| [`docs/install-checklist.md`](docs/install-checklist.md) | Manual installation |
| [`docs/prior-art.md`](docs/prior-art.md) | Related projects and references |
| [`docs/roadmap.md`](docs/roadmap.md) | Original plan, in dependency order |

## Known limitations

- Mesa and intel-media-driver don't know the Lakefield GPU ID (`0x9840`) yet. Until they do,
  the GPU is presented to them as a known ID (`userspace/systemd`, `userspace/modprobe.d`).
- The Bluetooth link runs at 115200 baud in normal operation; a higher operational speed is
  experimental (`hci_uart.intel_ccp_speed`).
- The patches are not upstream. Some are general fixes and could be submitted
  (e.g. the ACPI `_S0W` handling and the eDP PSR interrupt registers); others are Lakefield/Fold specific.

## Credits

This builds on:
- [lakefield-kernel-fixes](https://github.com/Independent-Scientist/lakefield-kernel-fixes) and
  [galaxy-book-s-linux](https://github.com/franke7777/galaxy-book-s-linux) — earlier Lakefield work
  on the Samsung Galaxy Book S (several patches derive from or follow them);
- the `hci_intel` CcP/serdev series by Cai Yu ([bluez/bluetooth-next#821](https://github.com/bluez/bluetooth-next/pull/821));
- the upstream ISH fixes backported in patches 0001–0002;
- [ithc-linux](https://github.com/quo/ithc-linux) for touch.

More in [`docs/prior-art.md`](docs/prior-art.md).

## Repository policy

- Only this project's own work: patches, packaging, tools, configuration and documentation.
- No vendor binaries, driver files, firmware or dumps. Firmware the hardware needs is obtained
  from its original source and documented, never committed (`x1fold-sst-firmware` downloads it
  from Lenovo when it is built).
- No upstream kernel source: patches against a pinned kernel release.
- `work/` (gitignored) holds local vendor files, dumps and the kernel tree.

## License

GPL-2.0-only (see [`LICENSE`](LICENSE)), like the kernel the patches modify. This covers the
patches, the packaging, the tools, the configuration and the documentation. Third-party work the
patches build on keeps its original authorship, as recorded in each patch.
