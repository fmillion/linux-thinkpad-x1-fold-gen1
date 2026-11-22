# Userspace configuration

Install these on a system running a kernel with `patches/6.18.64` applied.

| File | Install to | Purpose |
|---|---|---|
| `udev/60-thinkpad-x1-fold.rules` | `/etc/udev/rules.d/` | ISH may wake the system (lid open, ECLite events) |
| `modprobe.d/thinkpad-x1-fold-i915.conf` | `/etc/modprobe.d/` | `i915.lkf_chipset_id=0x4e71` so intel-media-driver (VA-API) accepts the GPU |
| `systemd/thinkpad-x1-fold-gpu-id.service` | `/etc/systemd/system/` (enable) | Presents PCI ID 0x4e71 in sysfs so Mesa accepts the GPU (interim) |
| `modprobe.d/thinkpad-x1-fold-audio.conf` | `/etc/modprobe.d/` | AVS audio driver (needs SST firmware: `tools/extract-sst-firmware.sh`) |
| `wireplumber/51-thinkpad-x1-fold.conf` | `/etc/wireplumber/wireplumber.conf.d/` | stable DMIC node name, hide codec input, "Speakers" / "External Display" sink names |
| `pipewire/51-thinkpad-x1-fold-mic.conf` | `/etc/pipewire/pipewire.conf.d/` | "Built-in Microphones": 4 DMICs → mono, +18 dB, default source |
| `helper/thinkpad-fold-helper` (+ `.desktop`) | `/usr/local/bin/`, `/etc/xdg/autostart/` | docked mode / rotation / touch-mapping policy |
| `udev/61-thinkpad-x1-fold-hdmi-audio.rules` | `/etc/udev/rules.d/` | switch the display-audio outputs on (IEC958) |
| `sysctl/90-thinkpad-x1-fold-lockup-debug.conf` | `/etc/sysctl.d/` | *optional debug aid*: lockup → panic → log in EFI pstore |
| `sddm/10-thinkpad-x1-fold-wayland.conf` | `/etc/sddm.conf.d/` | Wayland (KWin) greeter: correct cursor on the upside-down panel |
| `plasma/thinkpad-x1-fold-gpu.sh` | `~/.config/plasma-workspace/env/` | **Only for render-only mode** (`i915.lkf_display=0`): KWin renders on i915, scans out via simpledrm |

The two ID workarounds go away once Mesa and intel-media-driver know `0x9840`.
Since patch 0019 i915 drives the X1 Fold's DSI panel by default (`i915.lkf_display=-1` = auto), and since
patch 0040 also the USB-C DisplayPort outputs (`i915.lkf_tc=-1` = auto).
Fallbacks on the kernel command line: `i915.lkf_display=0` (render-only, simpledrm keeps the
firmware framebuffer — then also install the Plasma env script), `i915.enable_dc=0` (no display
DC states), `module_blacklist=i915` (no GPU driver at all).

If KWin shows the desktop upside down, it has a stale saved output config from simpledrm
sessions: `kscreen-doctor output.DSI-1.rotation.inverted` (or System Settings → Display).

Audio: also set `amixer -c DMIC cset numid=1 2147483647` once and `alsactl store` (see docs/audio.md).
