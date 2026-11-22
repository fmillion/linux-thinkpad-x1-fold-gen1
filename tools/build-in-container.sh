#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the linux-x1fold packages in a throwaway archlinux:latest container (Docker), leaving the
# build host's own system untouched.
#
#   tools/build-in-container.sh [<workdir>] [<jobs>]
#
# <workdir> (default ~/x1fold-build) gets repo/ (a copy of this checkout), src/ (build tree,
# tens of GB) and out/ (the packages).
set -euo pipefail
W=$(realpath -m "${1:-$HOME/x1fold-build}"); J=${2:-$(nproc)}
here=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
mkdir -p "$W/repo" "$W/src" "$W/out"
rsync -a --delete --exclude /work/ --exclude /.password "$here/" "$W/repo/"
cat >"$W/build.sh" <<EOS
#!/bin/bash
set -euxo pipefail
pacman -Syu --noconfirm --needed base-devel git rust rust-bindgen rust-src bc cpio gettext \\
  libelf pahole perl python tar xxhash xz zlib zstd openssl
useradd -m builder
rm -rf /build/src/pkg && cp -r /build/repo/packaging/arch/linux-x1fold /build/src/pkg
chown -R builder: /build/src /build/out
su builder -s /bin/bash -c '
  set -euxo pipefail
  git config --global --add safe.directory "*"
  gpg --auto-key-locate clear,wkd --locate-keys torvalds@kernel.org gregkh@kernel.org
  cd /build/src/pkg
  X1FOLD_REPO=git+file:///build/repo MAKEFLAGS=-j$J PKGDEST=/build/out makepkg --noconfirm
'
EOS
docker run --rm --name x1fold-kbuild -v "$W:/build" archlinux:latest bash /build/build.sh
ls -l "$W/out"
