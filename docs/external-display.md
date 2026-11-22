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

## Warning: do not read the TC PHY space from userspace (hard hang, 2026-11-22)
`tools/tc-phy-windows.py` (write `HIP_INDEX`, then read 0x168000–0x168fff for each window)
**hung the machine with a corrupted display** on the first pass (TC1, no output written). At that
point i915 held no AUX/TC power well and had not taken PHY ownership through the FIA
(`DFLEXDPCSSS`), so the PHY block was most likely unpowered or owned by the PD side, and the
accesses stalled the fabric. Only probe the PHY from inside i915, after the AUX power well is up
and ownership is taken (the TGL `intel_tc` sequence). The script is kept only as a record of
what not to do. PHY identification moves to static analysis of the Windows driver.

## Type-C PHY = Dekel (TGL-style), confirmed from the Lakefield GOP (static analysis)
Source: `IntelGopDriver.efi` from the N2PET64W BIOS image (LKF-only code). Its PHY accessors
(read at RVA 0x11cf0, write 0x11d64, read-modify-write 0x11de4) take a port and a
`{offset, window}` descriptor:
| DDI | PHY base | HIP_INDEX (0x1010a0) field | = |
|---|---|---|---|
| D (port 3) | 0x168000 | bits 3:0 | TC1 |
| E (port 4) | 0x169000 | bits 11:8 | TC2 |
This is exactly i915's TGL Dekel layout (`_DKL_PHY1_BASE`, `HIP_INDEX_VAL(tc, v) = v << 8*tc`).
No ICL MG PHY address (0x168a00, 0x1683a0, 0x1688d4, 0x16812c) occurs in the GOP.

Registers the GOP programs (window<<12 | offset): `DKL_TX_DPCNTL0/1/2` for both lanes
(0x02c0–0x02c8, 0x12c0–0x12c8), `DKL_CLKTOP2_HSCLKCTL` 0x20d4, `DKL_CLKTOP2_CORECLKCTL1` 0x20d8,
`DKL_REFCLKIN_CTL` 0x212c, `DKL_PLL_DIV0/DIV1/SSC/BIAS/TDC_COLDST_BIAS` 0x2200–0x2218 — all as in
i915's TGL Dekel code — plus 0x2130, 0x2208, 0x220c, 0x222c, 0x2244, 0x224c, which i915 leaves at
their defaults (check if link training fails). PLL enable is `MG_PLL_ENABLE0` 0x46030 (ICL/TGL).

### Implementation plan (i915)
- LKF ports: A (DSI), B (combo), D→TC1, E→TC2; `port_mask` adds D/E; port→TC mapping
  `port - PORT_D` (ICL uses `port - PORT_C`); HPD pins D→`HPD_PORT_TC1`, E→`HPD_PORT_TC2` in the
  gen11 DE HPD block (TC HPD only — no Thunderbolt, no PCH TC).
- PHY: a `dekel` predicate (DISPLAY_VER >= 12 **or Lakefield**) wherever i915 chooses Dekel over
  MG (DDI buffer translations/signal levels, DP mode, PLL read/write/compute in the dpll manager,
  power-gating/`TC_COLD`).
- TC mode: the ICL FIA ops (DFLEXDPSP live state / DFLEXDPCSSS ownership / DFLEXDPPMS ready),
  DP alt mode only; legacy and TBT modes not present.
- PLLs: EHL combo DPLL0/1/4 for port B, `MG_PLL1/2` (0x46030/0x46034) as Dekel PLLs for D/E.

## Bring-up log (i915.lkf_tc, patches 0031-0036)
Method: one-shot GRUB entry booting with `modprobe.blacklist=i915 systemd.unit=multi-user.target`,
netconsole (UDP to the dev host) + `ssh dmesg -w`, then `modprobe i915 lkf_tc=1 drm.debug=0x06`
by hand. A hang only costs a power cycle; the next boot is the normal entry.
| Run | Result | Cause → fix |
|---|---|---|
| boot with lkf_tc=1 | hard hang in the initramfs, nothing logged | → move the test to a manual modprobe with netconsole |
| 1 | AUX/EDID/FIA fine; `PLL 3 not locked`, training fails, hang | TGL Dekel PLL values written — the LKF TC PLL has the **ICL MG layout** behind the Dekel window → GOP 38.4 MHz table (0032) |
| 2 | divide-error oops in `hsw_compute_linetime_wm` | `port_clock` decoded with the ICL MG decoder = 0 → table-based frequency (0033) |
| 3 | PLL locks; `Unclaimed read 0x64340`, DDI BUF D never active | per-port `DP_TP_CTL` does not exist: LKF has the **TGL transcoder interface** (per-transcoder DP_TP, TGL port/clock select encodings) (0034) |
| 4 | **link training passes**, picture on the external monitor; pipe B reads back inactive, no vblank IRQs (flip timeouts) | transcoder/pipe B domains hang off PW_2, which never accepts a request → report PW_2 on (0035) |
| 5 | full boot into SDDM with `i915.lkf_tc=1`: DSI-1 + DP-1 on pipes A/B, no errors | — |

Lakefield's external display path, as established:
- **PHY addressing / TX / DP mode:** TGL Dekel (HIP_INDEX windows at 0x168000/0x169000;
  `DKL_TX_DPCNTL0/1/2`, `DKL_DP_MODE`, `DKL_CMN_UC_DW_27` health), own swing table, DPCNTL2 bit 2 set.
- **PLL:** ICL MG register semantics in the Dekel PLL window; GOP table for 1.62/2.7/5.4/8.1 GHz.
- **FIA, TC HPD, DDI_CLK_SEL, MG_PLL_ENABLE:** ICL.
- **Transcoder side:** TGL (per-transcoder DP_TP_CTL, TRANS_DDI_FUNC_CTL port bits 31:27,
  TRANS_CLK_SEL (port+1)<<28).
- **PW_2:** absent; transcoders B/C work without it.
