# ThinkPad X1 Fold Gen 1 — Findings Log

Running log of what we learn about the hardware and how Windows drives it.
Target kernel: **Linux 6.18.64 LTS**. Unit under test: `20RK000LUS`, BIOS `N2PET64W (1.36)`
(2026-08-26), Windows 11 build 28000.

Conventions: **[obs]** = observed on our unit; **[ext]** = from external source (URL given);
**[hyp]** = hypothesis, not yet verified.

---

## 1. Hardware inventory (from Windows PnP) [obs]

| Function | Windows device / HW ID | Windows driver (orig. INF) | Linux status / candidate |
|---|---|---|---|
| SoC | Intel Core i5-L16G7 (Lakefield, 1+4 hybrid) | `lakefieldsystem.inf` | — |
| GPU | `PCI\VEN_8086&DEV_9840&SUBSYS_22C617AA` "UHD Graphics" (Gen11) | `iigd_dch.inf` 31.0.101.2130 + Lenovo ext `iigd_ext.inf` | **No i915 support upstream** (see §3) |
| Panel | `MONITOR\LEN4142` "OLED Display 1536x2048", LGD 13.3" QXGA OLED, DolbyVision 300 nit | `tplcd.inf` (Lenovo monitor INF; only modes/ICC/HDR) | Panel is **portrait-native 1536x2048** |
| Touch + pen | `PCI\VEN_8086&DEV_98D0` Intel Precise Touch & Stylus (THC) → HID touch screen + pen + vendor collections; Wacom service | `intelthcbase.inf` 3.0.100.247, `wtabletserviceisd.inf` | out-of-tree `quo/ithc-linux` [ext] |
| Sensor hub | `PCI\VEN_8086&DEV_98FC` Intel ISH ("Integrated Sensor Solution"), 4× "HID Sensor Collection V2" `HID\Vid_8087&Pid_0AC2` | `ish.inf`, `ish_busdriver.inf`, `hid_pci.inf` 3.1.0.4352 | `intel-ish-hid` — **98FC not in ID table** [ext] |
| EC Lite | `ACPI\INT3538` "Intel ECLite Mail Box" | `eclite.inf` 1.0.10099.193 | `intel_ishtp_eclite` matches `INTC1035` only [ext] — battery likely depends on this |
| I2C HID (STMicro) | `ACPI\STME9100` → vendor-defined HID collections (Col01 vendor, Col02 generic) | inbox `hidi2c` | `i2c-hid-acpi` should bind; **purpose unknown** [hyp: keyboard-presence / hall sensor] |
| Keyboard dock | `ACPI\LEN009E` "Lenovo Device Dock", class `VHIDDock`, KMDF + `vhf` lower filter → `HID_DEVICE_SYSTEM_VHF` | `vhiddock.inf` 1.0.0.9 (INF comment: "To be uncommented on Win10X") | **None.** Prime RE target |
| Intel HID | `ACPI\INT33D5` (INTC816 collections: kbd, consumer, system ctrl, radio, vendor) | `hideventfilter.inf` 2.2.2.9 | `intel-hid` (tablet-mode / 5-button) |
| Lenovo Fn keys | `ACPI\LEN0130` | `fn.inf` (TPHKLOAD service) | [hyp] `thinkpad_acpi` HKEY |
| Lenovo PM | `ACPI\LEN026A` | `ibmpmdrv.inf` | [hyp] thinkpad_acpi-adjacent |
| Lenovo ITS | `ACPI\LEN0101` (Intelligent Thermal Solution / DYTC) | `litsdrv.inf` | `thinkpad_acpi` DYTC / platform_profile |
| Lenovo Smart Standby | `ACPI\LEN0111` | `smartstandbycomponent.inf` | not needed |
| Thermal | DPTF `INT3400/3403/3407/3409/3532`, proc participant `PCI 8086:9820` | `dptf_*.inf` | `int340x_thermal` |
| Audio controller | `PCI\VEN_8086&DEV_98C8` Intel SST | `intcaudiobus.inf` 10.28.0.6539, `intcoed.inf` | SOF has no LKF; **AVS** supports LKF (needs `intel/avs/lkf/dsp_basefw.bin`) [ext] |
| Codec | Realtek `10EC:0287` (ALC287 / marketed "ALC3306"), subsys `17AA:22C6` | `hdxlvsst.inf` 6.0.9225.1 + Dolby + Realtek APOs | `snd-hda-codec-realtek` — quirks for 17aa:22c6 TBD |
| DMIC | SST DMIC endpoint + Fortemedia APO (`fmapo.inf`, `intcdmicext_th.inf`) | — | AVS/SOF DMIC; Fortemedia = software beamforming (APO), not hardware |
| BT audio | SST BT audio endpoint (offload) | `intcbtau.inf` | n/a on Linux (host BT stack) |
| WiFi | `PCI 8086:2723` AX200 | `netwtw08.inf` | `iwlwifi` ✔ |
| Bluetooth | `ACPI\INT33E4` → UART H4 (`iBTSerialBus\UART_H4`) on LPSS UART | `ibtuart.inf` 23.40.0.2 | `hci_intel` lacks serdev/variant 0x14; out-of-tree series exists [ext] |
| Camera | USB `04F2:B6D2` (Chicony/SunplusIT) RGB + IR | `spuvcbvmerge*.inf` | `uvcvideo` ✔ (expected) |
| USB | xHCI `8086:98ED`, hub `0424:2422` | inbox | ✔ |
| LPSS | I2C `98C5/98C6/98E8/98E9/98EB`, SPI `98AA/98AB`, UART `98A8/98A9`, GPIO `INT34C4` | `ialpss2_*_lkf.inf` | `intel-lpss-pci` / `pinctrl` — verify IDs present |
| Battery / AC | `PNP0C0A` / `ACPI0003` via inbox `cmbatt` | — | `acpi battery` — but may need ECLite/ISH first [ext] |
| Keyboard (BT) | Lenovo Fold Mini Keyboard (TK008) BLE HOGP `VID 17EF PID 60ED` (kbd, consumer, touchpad, mouse) | inbox | `hid-generic` over BLE [hyp ✔] |
| Misc | WMI `PNP0C14` ×5, Lid `PNP0C0D`, HID buttons `ACPI0011` | inbox | — |

Unused / absent: Lenovo DPR (`dprcomponent.inf`) targets a Quectel/Foxconn **SDX55 5G modem**
(`PCI 105B:E0AB`) not fitted on this unit.

## 2. Lenovo userland: Mode Switcher [obs]

`C:\Program Files\Lenovo\Mode Switcher\` v2.0.0.21: .NET 4.8 `LenovoModeSwitcher.exe`, native
`ModeLib.dll`, `ModeSwitcherLauncherService.exe` (auto-start service).
UI strings reveal the feature set:

- Modes: **Single screen**, **Split screen**, **Flipped split screen** (two virtual halves of the panel).
- Posture icons: **Book** (full/split), **Clamshell** (full/split).
- "Display scale — Enhance your view by selecting a display scale option **when the keyboard is
  docked**" (100–300 %, or "same as full screen").
- "Device Dock Third Party Notice" ties it to the `VHIDDock` driver.

So Windows' docked behaviour = (dock signal from `LEN009E`/VHIDDock) + (Mode Switcher reconfiguring
the display). Next: decompile ModeLib to see *how* it shrinks the desktop (CCD/SetDisplayConfig,
custom mode, or Intel escape).

## 3. Upstream status (summary of external research)

See `docs/prior-art.md` for links. Headlines:

- **GPU 8086:9840 is not in i915's PCI ID tables** in v6.18; `sound/hda/core/i915.c` deny-lists LKF.
  The Galaxy Book S (same i5-L16G7) community has (a) render-only bring-up via the EHL profile
  with simpledrm for scanout, and (b) a 7-patch "impersonation" series lighting a **MIPI-DSI** panel.
  **Whether the Fold's panel is eDP or DSI is the first thing to establish** (VBT).
- **ISH 8086:98FC is missing** from `intel-ish-hid` ID table; Galaxy Book S binds via `new_id`
  and adds `INT3538` to `intel_ishtp_eclite` → battery/AC/UCSI appear.
- `hid-sensor-custom-intel-hinge` exists upstream (Intel custom hinge sensor) — check whether
  Fold firmware exposes it.
- Fold **Gen 2** keyboard-on-screen: thinkpad_acpi patch (not in 6.18) reading
  `\_SB.DEVD.GDST`, event hkey `0x60c0`. Check whether Gen 1 DSDT has a similar method on
  `LEN009E`.
- `intel_pmc_core` / `intel_idle` have no Lakefield entries (S0ix).

## 4. Keyboard dock detection — full chain [obs]

### 4.1 Firmware side (DSDT, BIOS N2PET64W 1.36)
- `\_SB.DEVD` (`_HID LEN009E`) lives in an **SSDT** (not the DSDT; DSDT only has
  `External (_SB_.DEVD)` / `External (_SB_.DEVD.DOST)`). Same object name the Fold 16 (Gen 2)
  thinkpad_acpi patch uses.
- The EC is **Intel ECLite running on the ISH** (`\_SB.ECLT`, `_HID INT3538`,
  `_DEP \_SB.PCI0.ISHD`). Its ACPI OpRegions: command space `0x9F` (`CMND/OFST/LNTH/COMP`) and
  data space `0x9E` (0x1A8 bytes: battery, charger, UCSI mailbox, thermals, status bits).
- ECLite data byte `0x162`, bit 1 = **`KBDT`** (keyboard detect). Neighbours: `HPLD` (bit 2),
  `HPAC` (4), `BTST` (5), `PSST` (6). Byte `0x160`: `KBLT`, `BTPW`, `FNKC`, `HUBS`, ….
- ECLite event `0x2B` (in the ECLT event dispatcher) → `\_GPE.SDOS()`:
  `ECLC(1,0,0x162,1)` (refresh 1 byte at 0x162) → `KBDT==1 ? DOST=0 : DOST=1` →
  `Notify(\_SB.DEVD, 1)` (Device Check).
- ⇒ **Dock detection, battery and AC all depend on ISH + ECLite working on Linux.**

### 4.2 Windows driver `VHIDDock.sys` 1.0.0.9 (Ghidra)
KMDF driver on `ACPI\LEN009E` with `vhf` lower filter. PDB path
`…\_Device_Dock_Multibranch_develop\LnvDockDevice\driver\…`.
- Registers ACPI notify callback; on `Notify(DEVD, 1)` evaluates **`GDST`** and completes pended
  user requests with the new 1-byte state.
- Evaluates ACPI methods via `IOCTL_ACPI_EVAL_METHOD`:
  - `GDST()` → Integer (0/1) — dock state.
  - `GDSZ()` → Package of 4 Integers — **occlusion rectangle (x, y, w, h) in panel pixels**.
  - `NSMC(Integer)` — called on user request (Mode Switcher informs firmware of a mode change;
    semantics TBD; **do not call blindly**).
- Device interface `{b98fa811-f3bd-4fec-8cd3-900cc355e58b}`, restricted to custom capability
  `microsoft.hsaTestCustomCapability_q536wpkpf5cy2`. Buffered IOCTLs:
  | IOCTL | Action | Buffer |
  |---|---|---|
  | `0xFFDC6000` | GDST | out 1 byte |
  | `0xFFDC6004` | GDSZ | out 16 bytes (4×u32) |
  | `0xFFDC600A` | wait for dock change (inverted call) | out 1 byte |
  | `0xFFDC600E` | NSMC(arg) | in u32 |
- VHF HID report descriptor (112 bytes) = **HID "Device Dock" application collection**
  (Generic Desktop usage 0x11), Report ID 1:
  Dockable Device Unique ID (0xD0, 8 B), Vendor ID (0xD1, u16), Primary Usage Page (0xD2, u16),
  Primary Usage ID (0xD3, u16), **Docking State** (0xD4, 1 bit) + 7 pad,
  **Display Occlusion** (0xD5) physical collection: X (0x30), Y (0x31) [logical 0..32767,
  physical 20.40 cm × 27.00 cm], Width (Digitizer 0x48), Height (Digitizer 0x49).
  This is Windows' standard keyboard-occlusion mechanism; the shell shrinks the work area.

### 4.3 Live values (probe via the IOCTLs above, read-only)
- `GDST = 1`, `GDSZ = (0, 1006, 1536, 1042)` ⇒ in native (portrait 1536×2048) scan-out
  coordinates the keyboard covers rows **1006–2047**; usable area = **1536×1006 at the top**.
  - **Confirmed by toggling:** docked → `GDST=1`, desktop `1536x1006`; undocked → `GDST=0`,
    desktop `1536x2048`. **`GDSZ` is static** `(0, 1006, 1536, 1042)` in both states (it describes
    where the keyboard *would* sit, not whether it is there).

### 4.4 Linux plan (draft)
1. ISH: add `8086:98FC` to `intel-ish-hid`; verify ISH firmware is BIOS-loaded on LKF.
2. ECLite: add `INT3538` to `intel_ishtp_eclite` ACPI match → OpRegions 0x9E/0x9F served.
3. Dock: small platform driver (or thinkpad_acpi extension, like the Gen 2 patch) binding
   `LEN009E`: on notify evaluate `GDST`/`GDSZ`; expose `SW_TABLET_MODE`-style input switch +
   sysfs `docked` and `occlusion` (x,y,w,h). Optionally emulate the HID Device Dock collection
   via a uhid-like in-kernel HID device so userspace sees the same thing Windows does.
4. Userspace (KDE): on dock → set output to a custom mode / reserved area for the top 1536×1006
   region, lock rotation; on undock → full panel + rotation.

## 5. Display / panel [obs]
- `WmiMonitorConnectionParams.VideoOutputTechnology = 0x80000000` (INTERNAL), **not** 11
  (DisplayPort-embedded). Intel reports eDP as 11 ⇒ panel is very likely **MIPI-DSI**
  (consistent with Galaxy Book S Lakefield bring-up).
- Windows EDID is **synthesized** (no serial, empty descriptors) — typical of Intel's VBT-derived
  EDID for DSI panels. Mfr `LEN`, product `0x4142`, 2019. Single DTD:
  `1536x2048 @ 60.023 Hz, 215.000 MHz; H 1536+48+32+80 (htotal 1696) -hsync;
  V 2048+3+10+51 (vtotal 2112) -vsync`. Physical 20×27 cm.

### 5.1 VBT (carved from BIOS capsule `N2PET64W.bin`, `tools/vbt_extract.py`, decoded with igt `intel_vbt_decode`)
Capsule holds 3 VBTs (`$VBT LAKEFIELD`); the Fold's is the BDB **230** one (offset 0x6b34bc,
6664 B). The other two (BDB 227) describe 1920×1080 reference panels.
- Child devices: **MIPI-A (DVO 0x15), "MIPI output"** = internal panel; DP-D, DP-E = the two USB-C DP alt-mode ports.
- MIPI config (panel 0): **4 lanes, video mode, non-burst with sync events, RGB888**, no dual link,
  BTA disabled, PPS via PMIC (I2C bus 6), PPS delays 500/500/500/500 ms, cycle 5000 ms.
- MIPI sequences (v3): POWER_ON = GPIO idx0 #1, #3 high; INIT_OTP = GPIO idx0 #0 high, 200 ms,
  then ~40 **generic short writes (type 0x23)** that program a **TI SN65DSI86 DSI→eDP bridge**
  (by register map: `0x0A` refclk, `0x10=0x26` DSI 4-lane, `0x12/0x13` DSI clk range, `0x0D` PLL_EN,
  `0x5C` HPD disable, `0x74–0x78` native AUX write (DPCD), `0x93=0x30` 4 DP lanes, `0x94` DP rate,
  `0x96=0x0A` semi-auto link training, `0x20–0x3A` video timings 1536×2048 / sync 32,10 /
  porches 80,51,48,3); DISPLAY_ON = `0x5A=0x0D` (VSTREAM on); BACKLIGHT_ON/OFF = GPIO idx2 #2.
  ⇒ Real chain: **LKF DSI → SN65DSI86 → eDP → LGD OLED**. i915's VBT-driven DSI sequence
  execution can replay this; no `ti-sn65dsi86` drm_bridge needed. (Register decode from datasheet
  memory — TODO verify against the SN65DSI86 datasheet.)
- Backlight (block 43): **PWM from display engine, controller 0, 990 Hz**, min 3/255, active-high.
  (Galaxy Book S drives the same `BXT_BLC_PWM_*` controller.) OLED: verify that PWM really
  dims (vs DPCD AUX brightness through the bridge).
- Power conservation: **ALS on, LACE supported & enabled by default**, DPST no. LACE (local adaptive
  contrast) + ALS are candidates for the "flashes" seen in Edge on Windows — TODO test by
  disabling in Intel Graphics Command Center.
- **OEM custom modes (block 20)**: entry #1 = **1536×1006 @60, enabled in GOP/OS/VBIOS, LFP1**.
  This is the docked-keyboard mode.

### 5.2 Windows docked behaviour (live, interactive session)
- Docked desktop = **`1536x1006@60`**, orientation 0 (native), 150 % scale (logical 1024×671,
  work area 1024×623). Mode list also has native `1536x2048` + scaled modes.
- So Windows docks by **mode-setting to the VBT OEM mode**, and the Intel driver shows it
  top-aligned (rows 0–1005) above the keyboard, consistent with GDSZ `y=1006`.

### 5.3 Linux design idea
Expose a `1536x1006` mode on the DSI connector (from VBT block 20 or a DMI quirk) and implement
it in i915 with the pipe scaler at 1:1, window at (0,0) top-aligned (instead of centered pfit).
Then docking is a plain modeset — works with KWin, Mutter, wlroots and X11 alike, and the
compositor naturally lays out a 1536×1006 desktop.

## 6. Sensors [obs]
WinRT enumeration (interactive session):
- Accelerometer "Left" (default reading ≈ (0.03, −0.88, −0.47) g), Gyrometers "Left" + "Right",
  two Simple Device Orientation (software) sensors "Left"/"Right". No HingeAngleSensor,
  no light/compass/inclinometer.
- 4 ISH HID sensor collections (`HID\VID_8087&PID_0AC2`, UP 0x20). The two halves each have an IMU;
  posture/hinge must be derived from the pair (as Windows does). TODO: dump report descriptors on
  Linux to identify all 4 collections (expect: L accel+gyro, R accel+gyro, + custom sensors).
- `STME9100` (I2C1 @0x50, STMicro VID 0x0483): Col01 vendor page 0xFF00, **Col02 HID Lighting &
  Illumination (0x59) LampArray** — LED controller of some kind. Low priority.

## 7. Platform / EC [obs]
- **No ACPI EC (`PNP0C09`) at all.** Everything EC-ish goes through ECLite on the ISH:
  battery/AC, **LID** (`LID0._LID` → ECLite `HPLD`, bit 2 of 0x162, refreshed by event 0x26),
  dock (`KBDT`), thermals, UCSI mailbox.
- HKEY is `\_SB.HKEY` with `_HID LEN026A`, `MHKV=0x0100`, no `_CID`. thinkpad_acpi (6.18) only
  matches `IBM0068`/`LEN0068`/`LEN0268` ⇒ **thinkpad_acpi does not load**. Events queued via
  `MHKQ` (0x6022, 0x6030, 0x6032, 0x6040, 0x6050, 0x60D0 seen). Gen 1 does not emit 0x60C0 for
  docking; it notifies `\_SB.DEVD` instead.
- `LHKF` (`LEN0130`) is an empty stub device (Windows Fn-key service binds it).
- `DYTC` method exists (platform profiles) — reachable only if something binds HKEY.

## 8. Upstream gap summary for 6.18.64 (verified in tree)
| Item | 6.18.64 status | Patch needed |
|---|---|---|
| i915 GPU `8086:9840` | absent from `pciids.h`; no LKF platform | **large**: LKF platform + DSI (Galaxy Book S series as base) |
| HDA/i915 audio component | LKF deny-listed in `sound/hda/core/i915.c` | follows i915 |
| ISH `8086:98FC` | absent from `hw-ish.h` / `pci-ish.c` | 1-line ID add (+ verify FW is BIOS-loaded) |
| ECLite `INT3538` | driver matches only `INTC1035` | small |
| thinkpad_acpi `LEN026A` | not matched; also assumes EC | small–medium (HKEY only, no EC) |
| Dock `LEN009E` | nothing | new small driver (GDST/GDSZ, notify → input switch + sysfs) |
| intel-hid `INT33D5` | matched | — (check 5-button / tablet-mode behaviour) |
| Audio DSP `98C8` | AVS supports LKF; SOF does not | firmware `intel/avs/lkf/dsp_basefw.bin` + topology; codec quirk 17aa:22c6 |
| `intel_pmc_core`, `intel_idle` | no LKF | medium (S0ix) |
| Bluetooth `INT33E4` | `hci_intel` lacks serdev/variant 0x14 | out-of-tree series exists |
| Touch/pen THC `98D0` | no in-tree driver | out-of-tree `ithc` |


## 9. Linux live-boot results (Arch live USB, kernel 7.2.6-arch2, 2026-11-21)
Raw collection via `tools/collect-linux.sh` (kept in gitignored `work/linux-collect/`).
- Display: **simpledrm** on the GOP framebuffer, 1536×2048 XR24 (no i915). SDDM runs on it.
- Unbound PCI: GPU `9840`, THC `98d0`, ISH `98fc`, HDA/DSP `98c8`, MEI `98e0`, DPTF `9820`,
  SPI `98ab`/`98a4`, host bridge, LPC.
- Only `AC` power supply; no battery. `intel-hid` (INT33D5) and `soc_button_array` (ACPI0011 → 2×
  gpio-keys) bind. Lid switch present (`LID0`).
- Full SSDT set obtained. `SSDT4` ("LEN009E") defines `\_SB.DEVD`:
  `GDST` = refresh ECLite 0x162 → `DOST = (KBDT == 1) ? 0 : 1`; `GDSZ` = constant
  `Package {0, 0x3EE, 0x600, 0x412}`. **There is no `NSMC`** on this machine.
- `LEN009F` (`\_SB.MSKN`) = 5G modem stub, `_STA` 0 on this SKU.
- `STME9100` LampArray: 1 lamp, kind 6 (Notification), 1 mm bbox, min update 3 ms.

### 9.1 ISH bring-up — **works with only the PCI ID**
`echo "8086 98fc" > /sys/bus/pci/drivers/intel_ish_ipc/new_id`: firmware is BIOS-loaded,
`hid-ish` reports 4 HID devices; IIO: `accel_3d`, `gravity`, 2× `gyro_3d`, `relative_orientation`,
**`hinge`** (Intel custom sensor `INT-020b` → upstream `hid-sensor-custom-intel-hinge`, channels
hinge/screen/keyboard), plus ~20 Intel custom sensors (`0x2000e1`, no description strings) and
unbound `0x20008f`, `0x200035`. One `hid_field_extract() n (192) > 32` warning from hub 0006.
Hinge reads 0/0/0 so far (TODO: verify with physical posture changes).

### 9.2 ECLite — works with patch 0002
- With `INT3538` matched: UCSI comes up (2 USB-C source power supplies), but `BAT1._BIF/_BIX`
  failed: handler returned `-EINVAL` because the driver's 384-byte buffer is smaller than the
  Fold's 0x1A8 data region (reads at 0x186). Raising `ECL_DATA_OPR_BUFLEN` to 512 (9-bit
  offset/len in the message header) fixes it.
- **Battery works**: BAT1 Celxpert `LNV-5B10W13884`, Li-poly, 50.0 Wh design / 48.1 Wh full,
  20 cycles. (Live test needed a battery rebind because eclite was loaded late.)

### 9.3 Dock driver `drivers/lenovo-fold-dock` — works
Probe reads `GDSZ`, `GDST`; sysfs `keyboard_docked`, `occlusion`; KOBJ_CHANGE on change.
Deliberately not `SW_DOCK` (logind would treat "docked" as a docking station and ignore lid close).

### 9.4 Dock events end-to-end (live, eclite dyndbg)
- Each keyboard place/lift → ECLite **event 0x2B** over ISHTP → `intel_ishtp_eclite` evaluates
  `ECLT._DSM(91d936a7-…, rev 0, fn 43)` → `SDOS` → `Notify(\_SB.DEVD, 0x01)`.
- Bug found in first driver draft: registered `ACPI_DEVICE_NOTIFY` (≥0x80 only); `0x01` (Device
  Check) is a *system* notify. Fixed with `ACPI_ALL_NOTIFY` (devm). Polling `GDST` confirmed the
  state flips correctly (1→0→1→0→1 for two lift/place cycles).
- Periodic ECLite event `0x0F` (fn 15) every ~1–5 s (battery/thermal refresh; harmless).

### 9.5 s2idle and ECLite
- Suspend/resume (s2idle) works, but `PEPD._DSM` LPS0 **fn 3 (Screen Off)** / **fn 4 (Screen On)**
  each issue ECLite writes (`PLON` @0x15B, `HLCL` @0x14E = 0xA0 / 0x80) and `SDOS`; on Linux they
  time out (`[ish_rd] No response from firmware`, 2 s each) because Linux runs them from
  `acpi_s2idle_prepare_late()` / `restore_early()`, i.e. after `suspend_noirq`, when the ISH
  interrupt is masked. Windows sends display-off long before device suspend.
- Fix plan: DMI-quirked early LPS0 screen-off (in `.begin`) / late screen-on (in `.end`) for this
  machine, so ECLite still answers. Effect today: EC never learns we are in standby (power LED /
  standby behaviour) + ~4 s added to suspend/resume.

### 9.6 Hinge sensor
- Buffered read (trigger `hinge-dev5`, 10 Hz, on-change): channels `le:s16/32` (mask to 16 bits).
  Sample at ~100° open: **hinge 102°, screen 106–107°, keyboard 4°**. Units: degrees
  (scale 0.01745 rad). One-shot `in_angl*_raw` returns 0 (sync GET_REPORT not answered for this
  sensor) — use buffers.
