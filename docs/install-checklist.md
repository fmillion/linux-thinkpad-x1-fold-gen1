# Applying the Fold patches to a fresh Arch install

Done on 2026-11-22 for the external USB SSD install (`sdb`, mounted at `/mnt` from the live USB).
Reuse for the eventual internal-SSD install. The live USB itself is not modified by these steps.

## Prerequisites in the target
`linux-lts`, `linux-lts-headers`, `base-devel`, GRUB, `plasma`, `sddm`, `mesa`, `intel-media-driver`,
`libva-utils`, `iio-sensor-proxy`, **`linux-firmware` (at least `linux-firmware-intel`: iwlwifi,
i915 GuC/HuC/DMC, later audio/BT)**, a network service and `sshd` enabled.

## Kernel (`6.18.64-fold`)
1. Copy the module tree: `/usr/lib/modules/6.18.64-fold` (no `build`/`source` links), including
   `updates/i915.ko.zst` (patch 0006 build) and `updates/lenovo-fold-dock.ko.zst`.
2. `/boot/vmlinuz-linux-fold`.
3. `/etc/mkinitcpio.d/linux-fold.preset`:
   ```
   ALL_kver="/boot/vmlinuz-linux-fold"
   PRESETS=("default")
   default_image="/boot/initramfs-linux-fold.img"
   ```
4. `depmod 6.18.64-fold`; `mkinitcpio -p linux-fold`. (With the `kms` hook, our i915 is in the
   initramfs — fine, render-only mode is safe early.)
5. Make it the default: add `GRUB_TOP_LEVEL="/boot/vmlinuz-linux-fold"` to `/etc/default/grub`
   (GRUB ≥ 2.12; with `GRUB_DEFAULT=0` the top-level "Arch Linux" entry then boots it; `linux-lts`
   stays under "Advanced options"), then `grub-mkconfig -o /boot/grub/grub.cfg`.

6. Touch: build ithc against the kernel tree and install it to `updates/`:
   `tools/build-ithc.sh <kernel-tree> <ithc-checkout> <stage>`; copy `updates/ithc.ko*`; `depmod`.
   Needs patch 0022 in the kernel image (otherwise only `options ithc poll` works).

7. Audio firmware: mount the machine's Windows partition read-only and run
   `tools/extract-sst-firmware.sh <mountpoint>` (installs to `updates/intel/avs/lkf/`).

## Userspace (`userspace/`)
- `udev/60-thinkpad-x1-fold.rules` → `/etc/udev/rules.d/`
- `modprobe.d/thinkpad-x1-fold-i915.conf` → `/etc/modprobe.d/`
- `systemd/thinkpad-x1-fold-gpu-id.service` → `/etc/systemd/system/`, `systemctl enable`
- `sddm/10-thinkpad-x1-fold-wayland.conf` → `/etc/sddm.conf.d/`
- (render-only mode only) `plasma/thinkpad-x1-fold-gpu.sh` → `~/.config/plasma-workspace/env/`
  (owned by the user; the user's group is `users`, not the uid)
- The kernel image must include patch 0012 (panel orientation quirk, built-in) — i.e. build the
  full kernel from the series, not only modules.
