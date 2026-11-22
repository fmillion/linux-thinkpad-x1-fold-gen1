#!/bin/sh
# Build the out-of-tree ithc (Intel Touch Host Controller) module against a kernel tree.
#   tools/build-ithc.sh <kernel-build-dir> [<ithc-src-checkout>] [<install-mod-path>]
# Tested with github.com/quo/ithc-linux commit 6d53c9c on 6.18.64-fold.
set -eu
KDIR=${1:?kernel build dir}
SRC=${2:-$(dirname "$0")/../work/ext/ithc-linux}
DEST=${3:-}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp -r "$SRC/src/." "$W/"
make -C "$KDIR" M="$W" CONFIG_HID_ITHC=m modules
if [ -n "$DEST" ]; then
	make -C "$KDIR" M="$W" CONFIG_HID_ITHC=m INSTALL_MOD_PATH="$DEST" INSTALL_MOD_DIR=updates modules_install
else
	cp "$W/ithc.ko" .
fi
