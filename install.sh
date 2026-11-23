#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Install Linux support for the Lenovo ThinkPad X1 Fold Gen 1 on Arch Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/fmillion/linux-thinkpad-x1-fold-gen1/main/install.sh | sudo bash
#
# Run it on a freshly installed Arch system on the Fold, with a USB keyboard and a network
# connection (wired, or Wi-Fi, which works on the stock kernel). The Fold keyboard is Bluetooth
# and only works with the new kernel, so it is paired after the reboot. The script
#   1. installs the packages: from a binary repository if X1FOLD_REPO_URL is set, otherwise it
#      builds them from this repository (the kernel takes hours on the Fold itself);
#   2. always builds x1fold-sst-firmware locally (Intel firmware, downloaded from Lenovo);
#   3. makes linux-x1fold the default boot entry (GRUB or systemd-boot);
#   4. tells you how to pair the keyboard after the reboot.
#
# Environment:
#   X1FOLD_REPO_URL   pacman repository URL for prebuilt packages ($arch is expanded by pacman)
#   X1FOLD_REPO_KEY   key id signing that repository (fetched from keyserver.ubuntu.com)
#   X1FOLD_GIT        git URL of this project (default: GitHub)
#   X1FOLD_REF        branch or tag to build from (default: main)
#   X1FOLD_SST_FW_URL build the audio firmware from this copy of dsp_fw_release.bin (checksum-
#                     pinned) instead of Lenovo's driver download
#   X1FOLD_PLASMA     1/0: install the KDE Plasma integration (default: 1 if plasma is installed)
#   X1FOLD_FORCE      1: skip the hardware check
set -euo pipefail

X1FOLD_GIT=${X1FOLD_GIT:-https://github.com/fmillion/linux-thinkpad-x1-fold-gen1.git}
X1FOLD_REF=${X1FOLD_REF:-main}
X1FOLD_REPO_URL=${X1FOLD_REPO_URL:-}
X1FOLD_REPO_KEY=${X1FOLD_REPO_KEY:-}

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
ask()  { # ask "question" default(y/n) -> 0 for yes; reads the terminal even when piped
	local a d=$2
	if [[ -r /dev/tty ]]; then
		read -r -p "$1 [$([[ $d = y ]] && echo Y/n || echo y/N)] " a </dev/tty || a=
	else
		a=
	fi
	a=${a:-$d}; [[ $a = [yY]* ]]
}

# --- checks -------------------------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "run as root (… | sudo bash)"
[[ -f /etc/arch-release ]] || die "this installer is for Arch Linux"
family=$(cat /sys/class/dmi/id/product_family 2>/dev/null || true)
if [[ $family != "ThinkPad X1 Fold Gen 1" && ${X1FOLD_FORCE:-0} != 1 ]]; then
	die "this is not a ThinkPad X1 Fold Gen 1 ('$family'); set X1FOLD_FORCE=1 to continue anyway"
fi
builder=${SUDO_USER:-}
if [[ -z $builder || $builder = root ]]; then
	die "run through sudo from a normal user account (makepkg does not build as root)"
fi
if [[ -z ${X1FOLD_PLASMA:-} ]]; then
	pacman -Q plasma-workspace &>/dev/null && X1FOLD_PLASMA=1 || X1FOLD_PLASMA=0
fi

say "Installing build tools"
pacman -Syu --needed --noconfirm base-devel git innoextract python

work=$(sudo -u "$builder" mktemp -d -t x1fold-install.XXXXXX)
trap 'rm -rf "$work"' EXIT
say "Fetching $X1FOLD_GIT ($X1FOLD_REF)"
# shallow where the server supports it (not over plain/"dumb" HTTP)
sudo -u "$builder" git clone -q --depth 1 --branch "$X1FOLD_REF" "$X1FOLD_GIT" "$work/x1fold" 2>/dev/null ||
	sudo -u "$builder" git clone -q --branch "$X1FOLD_REF" "$X1FOLD_GIT" "$work/x1fold"

build() { # build <package dir> -> prints the built package files
	local d="$work/x1fold/packaging/arch/$1"
	( cd "$d" && sudo -u "$builder" env X1FOLD_REPO="git+file://$work/x1fold" \
		X1FOLD_REF="branch=$X1FOLD_REF" X1FOLD_SST_FW_URL="${X1FOLD_SST_FW_URL:-}" \
		makepkg --syncdeps --noconfirm --force >&2 )
	ls "$d"/*.pkg.tar.zst
}
# makepkg --syncdeps calls pacman through sudo as $builder: allow that for this run only
sudoers=/etc/sudoers.d/90-x1fold-install
printf '%s ALL=(root) NOPASSWD: /usr/bin/pacman\n' "$builder" >"$sudoers"
chmod 0440 "$sudoers"
trap 'rm -f "$sudoers"; rm -rf "$work"' EXIT

# --- packages -----------------------------------------------------------------------------
say "Building x1fold-sst-firmware (Intel audio DSP firmware, from Lenovo's driver package)"
pacman -U --noconfirm $(build x1fold-sst-firmware)

pkgs=(x1fold)
(( X1FOLD_PLASMA )) && pkgs+=(x1fold-plasma)

if [[ -n $X1FOLD_REPO_URL ]]; then
	say "Adding the [x1fold] repository"
	if [[ -n $X1FOLD_REPO_KEY ]]; then
		pacman-key --recv-keys "$X1FOLD_REPO_KEY" --keyserver hkps://keyserver.ubuntu.com
		pacman-key --lsign-key "$X1FOLD_REPO_KEY"
		siglevel="Required DatabaseOptional"
	else
		warn "no X1FOLD_REPO_KEY: the repository is used unsigned"
		siglevel="Optional TrustAll"
	fi
	if ! grep -q '^\[x1fold\]' /etc/pacman.conf; then
		printf '\n[x1fold]\nSigLevel = %s\nServer = %s\n' "$siglevel" "$X1FOLD_REPO_URL" >>/etc/pacman.conf
	fi
	say "Installing ${pkgs[*]}"
	pacman -Sy --needed --noconfirm "${pkgs[@]}"
else
	say "No binary repository given: building the packages from source"
	warn "the kernel build takes a long time on the Fold (hours); set X1FOLD_REPO_URL to avoid it"
	ask "Build linux-x1fold now?" y || die "cancelled"
	files=()
	for p in linux-x1fold x1fold-hwconfig x1fold; do
		mapfile -t -O "${#files[@]}" files < <(build "$p")
	done
	(( X1FOLD_PLASMA )) && mapfile -t -O "${#files[@]}" files < <(build x1fold-plasma)
	# all kernel split packages except the headers
	mapfile -t files < <(printf '%s\n' "${files[@]}" | grep -v -- '-headers-')
	say "Installing ${files[*]##*/}"
	pacman -U --needed --noconfirm "${files[@]}"
fi

# --- boot entry ---------------------------------------------------------------------------
kimg=/boot/vmlinuz-linux-x1fold
[[ -f $kimg ]] || die "$kimg missing: did the linux-x1fold install run mkinitcpio?"
if [[ -f /etc/default/grub ]] && command -v grub-mkconfig >/dev/null; then
	say "Making linux-x1fold the default GRUB entry"
	if grep -q '^GRUB_TOP_LEVEL=' /etc/default/grub; then
		sed -i "s|^GRUB_TOP_LEVEL=.*|GRUB_TOP_LEVEL=\"$kimg\"|" /etc/default/grub
	else
		printf '\n# ThinkPad X1 Fold: boot the patched kernel by default\nGRUB_TOP_LEVEL="%s"\n' "$kimg" >>/etc/default/grub
	fi
	grub-mkconfig -o /boot/grub/grub.cfg
elif command -v bootctl >/dev/null && bootctl is-installed &>/dev/null; then
	say "Adding a systemd-boot entry for linux-x1fold and making it the default"
	esp=$(bootctl --print-esp-path)
	opts=$(sed -E 's/(^| )(BOOT_IMAGE|initrd)=[^ ]*//g' /proc/cmdline)
	cat >"$esp/loader/entries/linux-x1fold.conf" <<-EOF
	title   Arch Linux (ThinkPad X1 Fold)
	linux   /vmlinuz-linux-x1fold
	initrd  /initramfs-linux-x1fold.img
	options $opts
	EOF
	bootctl set-default linux-x1fold.conf
	[[ $esp = /boot ]] || warn "the ESP is $esp, not /boot: make sure the kernel and initramfs are there"
else
	warn "no GRUB or systemd-boot found: add a boot entry for $kimg and /boot/initramfs-linux-x1fold.img yourself"
fi

# --- done ---------------------------------------------------------------------------------
say "Done"
cat <<'EOF'
After the reboot:
  * The panel, touch, audio, Wi-Fi, Bluetooth and USB-C displays should all come up.
  * Pair the Fold keyboard: hold its Bluetooth key until it blinks, then add it in
    System Settings -> Bluetooth ("Lenovo Fold Mini Keyboard"; type the shown PIN on the
    keyboard, then Enter). Without Plasma: bluetoothctl (agent KeyboardDisplay, scan le,
    pair/trust/connect <address>), see docs/bluetooth.md.
  * Optional: switch off Plasma's automatic suspend while setting up.
EOF
if ask "Reboot now?" y; then
	systemctl reboot
fi
