# Userspace configuration

Install these on a system running a kernel with `patches/6.18.64` applied.

| File | Install to | Purpose |
|---|---|---|
| `udev/60-thinkpad-x1-fold.rules` | `/etc/udev/rules.d/` | ISH may wake the system (lid open, ECLite events) |
| `modprobe.d/thinkpad-x1-fold-i915.conf` | `/etc/modprobe.d/` | `i915.lkf_chipset_id=0x4e71` so intel-media-driver (VA-API) accepts the GPU |
| `systemd/thinkpad-x1-fold-gpu-id.service` | `/etc/systemd/system/` (enable) | Presents PCI ID 0x4e71 in sysfs so Mesa accepts the GPU (interim) |
| `plasma/thinkpad-x1-fold-gpu.sh` | `~/.config/plasma-workspace/env/` | KWin renders on i915, scans out via simpledrm; `LIBVA_DRIVER_NAME=iHD` |

The two ID workarounds go away once Mesa and intel-media-driver know `0x9840`.
Escape hatch if the GPU misbehaves: add `module_blacklist=i915` to the kernel command line.
