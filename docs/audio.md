# Audio (Intel HDA/DSP 8086:98c8, Realtek ALC287, 4× DMIC)

## Hardware
- Controller `8086:98c8` (subsystem 17aa:22c6). Not in `snd_hda_intel`'s ID table; SOF has no LKF;
  **AVS** (`snd_soc_avs`) supports LKF (TGL ops, min FW 10.28.0.5646).
- Codec: **Realtek ALC287** on the HDA link (codec subsystem 0x17aa22c6). BIOS pin config: only
  pin 0x17 = internal speaker pair; no headphone jack (the Fold has USB-C audio only), no codec
  mics. Integrated class-D amp — no external smart amp (unlike the Galaxy Book S).
- Microphones: **4 PDM DMICs on the DSP** (NHLT DMIC endpoint). Distinct channels (correlation
  0.994–0.998).
- ACPI `HDAS.SNDW.SWD0..7` errors at boot are Intel reference-BIOS SoundWire placeholders.

## Firmware
linux-firmware's `intel/avs/lkf/` is empty in Arch's `linux-firmware-intel` 20261019 (and the
upstream LKF image is reportedly rejected by the CSE). Use the machine's own Windows SST package:
`intcoed.inf_amd64_*/Fw/dsp_fw_release.bin` — on our unit two packages: FW **10.28.0.5995**
(2021-06-30, driver 10.28.0.6539, active) and 10.28.0.4381 (too old). Install with
`tools/extract-sst-firmware.sh <mounted Windows>` → `/usr/lib/firmware/updates/intel/avs/lkf/dsp_basefw.bin`.
Not redistributed by this project.

## Bring-up (2026-11-22)
- Without config, `snd_soc_avs` loads but declines (dsp-config auto) → no card.
- `snd_intel_dspcfg dsp_driver=4` + firmware → AVS boots the DSP; cards `AVS PROBE`, `AVS DMIC`,
  `AVS HD-Audio`. Works even when switched at runtime *as long as no other driver touched the
  controller in this boot* (Galaxy Book S finding: AVS must be first).
- AVS asks for `intel/avs/hda-10ec0287-tplg.bin` (absent) → falls back to the generic HDA topology.
  Many "Endpoint format configuration not found" lines (topology variants vs NHLT) — harmless.
- Quirk lookup prints `picked fixup for PCI SSID 17aa:0000` under AVS; no ALC287 quirk exists
  for 22c6 and none appears needed.
- **Speakers**: work; at PipeWire's 40 % default they are quiet, at 100 % "much better".
- **DMIC**: `DMIC Volume` (Q1.31) starts at 0 → set to 2147483647 (0 dB), persisted with
  `alsactl store`. Start-up transient in the first ~0.5 s. Noise floor ≈ −75 dBFS; speech at
  normal distance ≈ −47 dBFS RMS / −30 dBFS peak per mic. +18 dB → clear.

- **PipeWire picks S32_LE (24-in-32) by default → static, no speech.** The 16-bit DMIC path
  (what `arecord -f S16_LE` used) is clean. The WirePlumber rule pins the raw DMIC node to
  `audio.format = S16LE`, 48 kHz, 4 ch.

## Persistent configuration (`userspace/`)
- `modprobe.d/thinkpad-x1-fold-audio.conf`: `snd_intel_dspcfg dsp_driver=4`.
- `wireplumber/51-thinkpad-x1-fold.conf`: stable node name `thinkpad_fold_dmic_raw` for the DMIC,
  hide the codec input, sink description "Speakers".
- `pipewire/51-thinkpad-x1-fold-mic.conf`: filter-chain mixing the 4 DMICs to mono, gain 2.0 each
  (≈ +18 dB), default source "Built-in Microphones" (`thinkpad_fold_mic`).
- `alsactl store` after setting `DMIC Volume` (restored by alsa-restore).

## Not done / ideas
- Speaker EQ/loudness (Windows uses Dolby + Realtek APOs); compare loudness with Windows.
- DMIC beamforming/noise suppression (Windows: Fortemedia APO).
- Suspend/resume audio check.
