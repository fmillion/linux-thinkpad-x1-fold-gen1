# Changes made to the Arch live USB during development

Everything below was added by this project's work (not by the user's own package
installs/upgrades). Use it to restore the live image. Verified against
`/var/log/pacman.log` and the filesystem on 2026-11-22.

## Packages installed
| Package | Why | Revert |
|---|---|---|
| `intel-media-driver` (+ dependency `intel-gmmlib`) | VA-API (iHD) testing | `pacman -Rns intel-media-driver` |

(`linux-lts`, `linux-lts-headers`, `yay-bin-debug`, `fzf`, `downgrade` and the 19:36 system
upgrade were done by the user, not by this work.)

## Kernel `6.18.64-fold` (side by side, default boot entry unchanged)
| Path | Revert |
|---|---|
| `/boot/vmlinuz-linux-fold` | `rm` |
| `/boot/initramfs-linux-fold.img` | `rm` |
| `/boot/grub/custom.cfg` (only our menu entry; file did not exist before) | `rm` |
| `/usr/lib/modules/6.18.64-fold/` (incl. `updates/i915.ko.zst`, `updates/lenovo-fold-dock.ko.zst`) | `rm -r` |

## Configuration
| Path | Purpose | Revert |
|---|---|---|
| `/etc/udev/rules.d/60-thinkpad-x1-fold.rules` | ISH wakeup | `rm`; `udevadm control --reload` |
| `/etc/modprobe.d/thinkpad-x1-fold-i915.conf` | `i915 lkf_chipset_id=0x4e71` | `rm` |
| `/etc/systemd/system/thinkpad-x1-fold-gpu-id.service` + `multi-user.target.wants/` symlink | Mesa PCI ID bind mount | `systemctl disable --now thinkpad-x1-fold-gpu-id; rm` the unit; `systemctl daemon-reload` |
| `~fmillion/.config/plasma-workspace/env/thinkpad-x1-fold-gpu.sh` | KWin render/scanout devices, `LIBVA_DRIVER_NAME` | `rm` |
| `/boot/initramfs-linux-fold.img` regenerated | — | removed with the kernel above |

Removed again during the work (nothing to revert): `/etc/modprobe.d/fold-i915-manual.conf`,
`~/.config/plasma-workspace/env/fold-gpu.sh`.

## Transient only (gone after reboot)
`/tmp/*` build dirs and logs; sysctl `kernel.hung_task_*`/`panic`; ISH `power/wakeup` sysfs writes;
dynamic-debug and `pm_debug_messages`; `fold-lid-inhibit` / `fold-lidlog` transient units;
`/run/fold-gpu-devid` bind mount from manual testing.

## Not touched
`/usr/local`, `/etc/mkinitcpio.conf`, `/etc/default/grub`, `/boot/grub/grub.cfg`, existing kernels.

## Windows (internal SSD)
`C:\Users\fmillion\fold-re\` — staging copies of drivers/ACPI tables, **including `MSDM` (the
Windows product key table)**. Delete when no longer needed.
