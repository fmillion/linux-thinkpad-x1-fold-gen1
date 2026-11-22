# Linux on the ThinkPad X1 Fold Gen 1

Out-of-tree kernel patches, small drivers and userspace configuration to make Linux usable on
the Lenovo ThinkPad X1 Fold Gen 1 (2020, types 20RK/20RL, Intel Lakefield i5-L16G7).

Target kernel: **Linux 6.18.64 LTS** (patches are against the pristine release tarball).

Status: **research / characterization**. See:
- [docs/findings.md](docs/findings.md): hardware and firmware findings (what Windows does and how)
- [docs/roadmap.md](docs/roadmap.md): planned work, in dependency order
- [docs/prior-art.md](docs/prior-art.md): existing community work we build on

## Repository policy
- No vendor binaries, driver files, or dumps; only our patches, tools and documentation.
- No upstream kernel source; patches against a pinned version.
- Firmware blobs, if ever needed, are gitignored and documented, not committed.
- `work/` (gitignored) holds local vendor files, ACPI/VBT dumps and the kernel tree.

## Tools
- `tools/vbt_extract.py`: carve Intel VBTs out of a BIOS image.
