# Migration: external USB SSD install → internal NVMe (2026-11-22)

Windows on `nvme0n1` (SK hynix 1 TB) was wiped after capturing what we may need
(`docs/windows-capture.md`). Procedure, run from the booted external-SSD install:

1. Tools: `pacman -S btrfs-progs arch-install-scripts gptfdisk dosfstools rsync`.
2. Partition: `sgdisk --zap-all`; p1 1 GiB `ef00` ESP (FAT32, label FOLDEFI); p2 rest `8304`
   (btrfs, label fold-root).
3. btrfs subvolumes `@` `/`, `@home`, `@log` `/var/log`, `@pkg` `/var/cache/pacman/pkg`,
   `@snapshots` `/.snapshots`; mount options `noatime,compress=zstd:1,discard=async`.
4. `rsync -aHAXx --numeric-ids --delete` of `/` (excluding /dev /proc /sys /run /tmp /mnt /media
   /var/tmp) and `rsync -rt` of `/boot` to the new ESP. 8.2 GB → 3.4 GB on btrfs (zstd).
5. Remove the copied `EFI/Arch` (that GRUB looks for its config on the external disk);
   `genfstab -U` (subvolid stripped); old fstab kept as `/etc/fstab.external`.
6. In `arch-chroot`: `mkinitcpio -P`; `grub-install --efi-directory=/boot
   --bootloader-id=Arch-internal`; `grub-mkconfig` (GRUB_TOP_LEVEL keeps linux-fold default;
   `rootflags=subvol=@` added automatically). btrfs is built into the kernel (`CONFIG_BTRFS_FS=y`).
7. `grub-install` puts the new entry first → restored external-first order and used
   `efibootmgr -n` (BootNext) for a one-time test boot.
- Plasma's default idle suspend kicked in during the long copy; use `systemd-inhibit` for long jobs.
- Same hostname, machine-id, SSH host keys and BT bond as the external install (it is a clone).
- **Verified 2026-11-22:** booted `Arch-internal` (Boot0002), root `nvme0n1p2` subvol `@`, all
  subvolumes with `noatime,compress=zstd:1,ssd,discard=async`; i915 display, battery, dock, sensors,
  AVS audio, touch (ithc IRQ), BT bond all intact; no failed units. BootOrder now 0002 (internal)
  first, 0001 (external) second as fallback.
