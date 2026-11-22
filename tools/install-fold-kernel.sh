#!/bin/sh
# Install a staged "-fold" kernel on an Arch (GRUB + mkinitcpio) system *alongside*
# the existing kernels, without regenerating grub.cfg or changing the default entry.
#
#   sudo tools/install-fold-kernel.sh <stage.tar.zst>
#
# The tarball contains: vmlinuz-linux-fold and lib/modules/<release>/...
# A GRUB entry is (re)written to /boot/grub/custom.cfg, which stock Arch grub.cfg
# sources via 41_custom. Remove that file and the three paths below to uninstall.
set -eu
TAR=${1:?stage tarball}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

tar -C "$WORK" -xf "$TAR"
REL=$(ls "$WORK/lib/modules")
[ "$(echo "$REL" | wc -w)" = 1 ] || { echo "expected one module dir, got: $REL"; exit 1; }
echo "Installing kernel release $REL"

rm -rf "/usr/lib/modules/$REL"
cp -a "$WORK/lib/modules/$REL" "/usr/lib/modules/$REL"
rm -f "/usr/lib/modules/$REL/build" "/usr/lib/modules/$REL/source"
depmod "$REL"
install -m 0644 "$WORK/vmlinuz-linux-fold" /boot/vmlinuz-linux-fold
mkinitcpio -k "$REL" -g /boot/initramfs-linux-fold.img

# Reuse root= and boot partition UUID from the existing default entry.
ROOTARGS=$(sed -n 's/^[[:space:]]*linux[[:space:]]\+\/vmlinuz-linux-lts[[:space:]]\+\(.*\)$/\1/p' /boot/grub/grub.cfg | head -1)
BOOTUUID=$(findmnt -no UUID /boot)
cat > /boot/grub/custom.cfg <<EOF
# Written by thinkpad-fold tools/install-fold-kernel.sh
menuentry 'Arch Linux, with Linux $REL (ThinkPad X1 Fold patches)' --class arch --class gnu-linux --class os {
	load_video
	set gfxpayload=keep
	insmod gzio
	insmod part_gpt
	insmod fat
	search --no-floppy --fs-uuid --set=root $BOOTUUID
	echo	'Loading Linux $REL ...'
	linux	/vmlinuz-linux-fold $ROOTARGS
	echo	'Loading initial ramdisk ...'
	initrd	/intel-ucode.img /initramfs-linux-fold.img
}
EOF
echo "GRUB entry written to /boot/grub/custom.cfg:"
cat /boot/grub/custom.cfg
echo "Default boot entry unchanged. To boot it once: grub-reboot \"Arch Linux, with Linux $REL (ThinkPad X1 Fold patches)\" (needs GRUB_DEFAULT=saved), or pick it in the menu."
