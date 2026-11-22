# Packaging

## Arch Linux

| Directory | Package(s) | Notes |
|---|---|---|
| `arch/linux-x1fold` | `linux-x1fold`, `linux-x1fold-headers`, `linux-x1fold-ithc` | Arch's `linux-lts` PKGBUILD, config and patches (pinned to the matching Arch tag) + `patches/<version>/` + `CONFIG_LENOVO_FOLD_DOCK=m`; ithc from a pinned upstream commit, built in the same run |
| `arch/x1fold-sst-firmware` | `x1fold-sst-firmware` | Downloads Lenovo's audio driver package `n2pa115w.exe` (SHA-256 pinned), extracts Intel's SST firmware 10.28.0.5995 with `innoextract`, checks its version. **Build on the target machine; do not host the built package** (Intel's firmware, not redistributable by us) |
| `arch/x1fold-hwconfig` | `x1fold-hwconfig` | `userspace/` files in their package locations (`/usr/lib/udev`, `/usr/lib/modprobe.d`, `/usr/share/{pipewire,wireplumber}`); the GPU ID service is enabled statically |
| `arch/x1fold-plasma` | `x1fold-plasma` | Helper (`/usr/bin`), autostart entry, SDDM Wayland drop-in |
| `arch/x1fold` | `x1fold` | Metapackage |

The PKGBUILDs that use this repository's files take them from git:
`X1FOLD_REPO` (default: the GitHub repository) and `X1FOLD_REF` (default: `branch=main`). To build
from a local checkout:

```sh
cd packaging/arch/linux-x1fold
X1FOLD_REPO="git+file://$(git rev-parse --show-toplevel)" makepkg -s
```

Versions: the kernel follows the pinned LTS release (`pkgver`), `pkgrel` counts our revisions.
A new LTS point release needs the patch series re-applied (and tested) first.

### Installer

[`../install.sh`](../install.sh) (run with `sudo` from a normal user):

- checks for Arch and an X1 Fold Gen 1 (DMI; `X1FOLD_FORCE=1` to skip);
- builds `x1fold-sst-firmware` locally;
- installs `x1fold` (+ `x1fold-plasma` if Plasma is installed) from a binary repository when
  `X1FOLD_REPO_URL` (and `X1FOLD_REPO_KEY`) are set, otherwise builds all packages from source;
- makes `linux-x1fold` the default boot entry (GRUB via `GRUB_TOP_LEVEL`, or a systemd-boot entry);
- prints how to pair the Fold keyboard after the reboot.

## Other distributions

Planned: Ubuntu (kernel `.deb` via `make bindeb-pkg` from the same patch series, configuration
packages), later Fedora (COPR). The patch series stays the single source.
