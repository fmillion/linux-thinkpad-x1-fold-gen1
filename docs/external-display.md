# External display over USB-C (DP alt mode) — characterization

Setup (2026-11-22): no dock; USB-C→HDMI adapter (343c:0000 "USB Type-C Digital AV Adapter",
DP alt mode + DP→HDMI) on one USB-C port, charger on the other. Linux 6.18.64-fold.
Registers read with `tools/mmio-read.py` (BAR0 via sysfs `resource0`, read-only).

## USB-C / alt mode: handled by the EC, already done
- UCSI (`ucsi_acpi`) lists port0/port1, each with a DP altmode (SVID ff01) on the *port*; the
  partner reports **0 alternate modes** — Linux sees/controls nothing.
- The adapter's billboard capability says `bmConfigured = 0x03` for SVID ff01 = **configuration
  successful**: the EC/PD controller entered DP alt mode by itself, no OS involvement needed.

## Display engine: the hot-plug is visible, i915 ignores it
| Register | Value | Meaning |
|---|---|---|
| `GEN11_DE_HPD_ISR` 0x44470 | 0x00010000 | bit 16 = **TC1 hot-plug live** (ICL layout) |
| `GEN11_DE_HPD_IMR/IER` 0x44474/0x4447c | 0xffffffff / 0x003f003f | masked; i915 never enabled TC HPD |
| `GEN11_TC_HOTPLUG_CTL` 0x44038 | 0 | TC HPD detection not enabled |
| `SHOTPLUG_CTL_TC` 0xc4034 (south) | 0x880 | written by GOP; south ISR 0xc4000 = 0 |
| FIA1 `PORT_TX_DFLEXDPSP` 0x1638a0 | 0x2f | TC1: **live state = DP alt mode** (bit 5), lanes 0xF (4 lanes to DP) |
| FIA1 `DFLEXDPPMS` 0x163890 | 0x1 | TC1 DP PHY mode status complete |
| FIA1 `DFLEXDPCSSS` 0x163894 | 0x1 | TC1 safe-state/ownership bit set |
| FIA2/FIA3 (0x16e8a0/0x16f8a0) | 0xffffffff | absent — one FIA, two TC ports |
| `HIP_INDEX` 0x1010a0 | 0x2 | PHY register window index written by firmware → **Dekel-style (TGL)** PHY access, not ICL MG |
| `DDI_BUF_CTL` D/E 0x64300/0x64400 | 0 | never enabled |
| `DPCLKA_CFGCR0` 0x164280 | 0x01c00400 | |

Conclusions:
- Lakefield has **ICL/TGL-style Type-C display**: FIA at 0x163000, TC HPD in the DE HPD block,
  VBT DP-D/DP-E flagged "USB type C" (AUX-D/AUX-E). The monitor is on **TC1**.
- i915 runs Lakefield as EHL (combo PHYs only, ports A–D, no TC): `DP-1` is a combo-PHY port
  that can never see this monitor.
- Needed in i915: a Lakefield TC port definition (DDI D→TC1, DDI E→TC2), TC HPD (DE HPD block),
  FIA handling (alt-mode only; no TBT), and the TC PHY/PLL programming — likely Dekel, to be
  confirmed from the Windows driver (`igdkmdn64.sys`, captured) and the PHY window contents.
