# i915 DSI display bring-up on the X1 Fold (Lakefield)

## Firmware (GOP) reference state — captured 2026-11-22 with `i915.lkf_dump=1`
Read at i915 MMIO probe, before i915 programs anything (render-only boot; simpledrm on the BOOTFB).

| What | Register(s) | Value | Meaning |
|---|---|---|---|
| Fuses | 0x42000 | 0x8d800000 | PG0/1/3/4 distributed, PG2 (PW_2) absent — same as Galaxy Book S |
| Power well ctl 2 | 0x45404 | 0x000000f3 | PW_2 neither REQ nor STATE |
| DDI_BUF_CTL A | 0x64000 | 0x80000001 | enabled |
| TRANS_DDI_FUNC_CTL DSI0 | 0x6b400 | 0x80030006 | enabled |
| DSI0 H timings | 0x6b000/08 | 0x069f05ff / 0x064f062f | htotal 1696, hactive 1536, hsync 1584–1616 |
| DSI0 V timings | 0x6b00c/14 | 0x083f07ff / 0x080c0802 | vtotal 2112, vactive 2048, vsync 2051–2061 |
| Plane 1A | 0x70180 / 0x70190 | 0x8400000a / 0x07ff05ff | enabled, 1536×2048 |
| DPLL0 | 0x164000/04 | 0x00a001d6 / 0x00000063 | DCO ≈ 9030 MHz (19.2 MHz ref), ÷7 → AFE ≈ 1290 MHz |
| DPCLKA_CFGCR0 | 0x164280 | 0x01c00400 | |
| SoC PWM backlight 1 | 0xC8250/54/58 | 0x80000000 / 0x4bc1 / 0x4bc1 | enabled, 19.2 MHz/19393 ≈ 990 Hz (VBT), 100 % duty |
| SoC PWM backlight 2 | 0xC8350.. | 0 | unused |
| MIPIO 0x160000.. | | all 0xffffffff | not implemented here |

### MCD D-PHY lanes (base 0x162280 + lane·0x200)
| Lane | SOFT_RST (+08) | TXRX_CTL (+10) | MST_SLV (+14) | TX_TIMING0..3 (+18..+24) |
|---|---|---|---|---|
| 0 (data0) | 0 | 0x1c0b | 1 | 0x0c1a0808 0x0a00001a 0x017f0001 0x00030200 |
| 1,3,4 (data) | 0 | 0x0c0b | 1 | 0x0c1a0808 0x0a00001a 0x017f0001 0x00030200 |
| 2 (clock) | 0 | 0x0c0b | 1 | 0x0c350808 0x0a001a1a 0x017f0001 0x00030200 |
CBBS_CLOCK_CTRL (0x162030) = 0x0c519300.

Galaxy Book S (1920×1080, ~887 Mb/s/lane) for comparison: data 0x08110505/0x0a000011, clock
0x08230505/0x0a001711, CBBS 0x0c518d00 — i.e. **panel/bit-rate specific**; hence snapshot/restore.

## Kernel approach (work tree branch `fold`, on top of patches 0001–0006)
- `i915.lkf_display` (display param, default 0): use `ehl_desc` for 0x9840 only when set;
  i915 core's render-only mode = Lakefield without i915 display.
- From the Lakefield kernel fixes series (applied with `git am`): SoC PWM backlight on PCH-less EHL,
  NULL `pch_hpd`, default procmon entry (no `UD1`), two DCS reads after transcoder setup. Ported:
  PW_2 "request not accepted" = absent gate (limited to Lakefield).
- New: MCD lane **snapshot** before `intel_power_domains_init_hw()` (only if DDI A enabled and
  lanes MST_SLV=1), **restore** in `gen11_dsi_enable_port_and_phy()` and at the end of
  `icl_combo_phys_init()` whenever DDI A is enabled (covers fastboot handover and DC exits).
  DMI fallback table = the values above.
- Open question: VBT GPIO ops are "native" on Gen11 → `SHOTPLUG_CTL_DDI` (0xC4030) for RESET and
  `PP_CONTROL` (0xC7204) for AVDD/BKLT — PCH registers; whether they exist on LKF is in the next dump.

## Test procedure
- Opt-in GRUB entry "linux-fold, i915 DISPLAY TEST" (`/etc/grub.d/41_thinkpad_fold_display_test`,
  temporary): `i915.lkf_display=1 i915.enable_dc=0 drm.debug=0x06 log_buf_len=16M`.
  Default entry stays render-only. Journal is persistent → read failed boots with `journalctl -b -1`.
- Temporary on the external install: `/etc/modprobe.d/zz-thinkpad-x1-fold-i915-debug.conf`
  (`lkf_dump=1`). Remove both after bring-up.

## Result — first i915 display boot (2026-11-22)
`i915.lkf_display=1 i915.enable_dc=0`: fastset refused (port clock 258171 vs 258000 kHz) →
**full modeset through the DSI enable path with the MCD restore → panel lit**.
`card1-DSI-1` connected 1536x2048@60.02, fbdev `i915drmfb`, `intel_backlight` max 19393 (= GOP PWM
period), "captured firmware MCD D-PHY state" logged.
- Dump (2nd boot): `SHOTPLUG_CTL_DDI` 0xC4030 = 0x4 and `PP_STATUS/PP_CONTROL` 0xC7200/04 =
  0x80000008/0x7 **exist** on LKF → VBT native GPIO ops land on real registers.
- **Panel is mounted upside down**: GOP `PLANE_CTL 1A` = 0x8400000a (`ROTATE_180`). Fixed with a
  `drm_panel_orientation_quirks` DMI entry (1536x2048, BOTTOM_UP) — kernel image rebuild.
  - SDDM (X11 greeter): picture upright via Xorg software rotation, **HW cursor not rotated**
    (Xorg limitation) → switch SDDM to its Wayland greeter.
  - KWin reused a stale per-user output config from the simpledrm sessions (same "no EDID"
    identity, `transform: Normal`), so it ignored the new panel orientation. Fixed by setting the
    output to inverted (`kscreen-doctor output.DSI-1.rotation.inverted`). Fresh users get the
    panel orientation as default.
- Raw scanout is upside down relative to the logical picture: the keyboard occlusion from `GDSZ`
  (logical rows 1006–2047) covers **raw rows 0–1041**. Matters for the docked mode.
- User report: desktop correct, **brightness slider drives the PWM**, compositing accelerated,
  video playback works, WebGL Fishbowl 1000 fish @ 60 fps.
- Noise to clean up: WARN in `gen9_wait_for_power_well_fuses` (PW_2), WARN in
  `assert_port_valid`, one unclaimed register, repeated "VBT claims internal and external
  displays on PHY A", SWSCI/PCODE timeouts.

## Power management with i915 driving the panel (2026-11-22)
- PPS fix (`intel_pps_setup`: PCH base for PCH-less EHL/LKF) removed `Unclaimed read 0x61204`
  during the DSI power-off sequence.
- **DPMS off/on** (`kscreen-doctor --dpms off/on`): full VBT power-off/on sequences
  (GPIO 2/0/3/1 off, 1/3/0/2 on), panel back clean, kernel log clean.
- **s2idle via power button**: suspended 58 s, resumed instantly with picture; **power LED pulsed**
  (first time on Linux) → platform reaches its proper standby once the display is really off.
  No dark wake on this path.
- **Lid-close path**: ECLite power-source event 0x11 follows ~2–4 s after the lid closes (EC
  changes charging/PD policy) → dark wake → KWin/powerdevil turn the panel off and re-suspend →
  on lid-open resume nobody turns the screen on (KWin waits for input). `kscreen-doctor --dpms on`
  then lights it immediately (kernel resume path incl. runtime D3/DC9 is fine).
  Fix candidates: userspace helper (screen on after lid-open resume, together with the dock
  daemon) and/or kernel dark-wake filtering of non-lid ECLite events.
- Runtime PM is active in display mode (GPU reaches DC9 with the screen off) and resumes cleanly.
- Still noisy: `gen9_wait_for_power_well_fuses` WARN (PW_2) on every suspend/resume;
  `Unclaimed read 0x6f400` (TRANS_DDI_FUNC_CTL of the eDP transcoder, absent on LKF).
