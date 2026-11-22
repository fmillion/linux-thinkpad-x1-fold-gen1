# What was kept from the Windows install (before wiping the internal SSD)

All of it is vendor material and lives only in the gitignored `work/vendor/` — never committed.

| What | Where (work/vendor/) | Why |
|---|---|---|
| 140 third-party DriverStore packages (3.0 GB; 1.3 GB as `windows/win-capture.tar.zst`): Intel graphics `iigd_dch` (igdkmdn64.sys) + `iigd_ext`/`cui`/`igcc`, Intel BT UART `ibtuart`, Intel SST `intcaudiobus`/`intcoed`/`intcdmic`/`intcbtau`, Realtek `hdxlvsst` (RTKVHD64.sys) + APOs, Dolby/Fortemedia APOs, Intel THC, ISH, ECLite, DPTF, HID event filter, Lenovo Fn/PM/ITS/VHIDDock/Smart Standby/PowerMgr, monitor INF, Wacom, LPSS, HECI, firmware capsules | `windows/win-capture.tar.zst` | RE for open items: Type-C DisplayPort (graphics), BT operational baud (ibtuart), speaker EQ/amp (Realtek), pen (THC/Wacom), thermal (DPTF) |
| Windows `SYSTEM` registry hive (27 MB) — **sensitive, local only** (no SAM/SECURITY) | inside the archive, `win/config/SYSTEM` | per-device driver parameters (graphics, BT, UCSI) |
| Earlier: drivers, Mode Switcher, ACPI, VBTs, BIOS capsule, SST firmware | `drivers/`, `modeswitcher/`, `acpi/`, `bios/`, `firmware/` | see findings |
| ESRT listing | `windows/esrt.txt` | capsule GUIDs for fwupd |

## Firmware updates without Windows (ESRT, 2026-11-22)
| ESRT | GUID | Version | Capsule kept |
|---|---|---|---|
| entry0 (system) | 8d34c220-8d03-4bfc-9de2-7db68b258e00 | 65572 = 1.36 | `N2PET64W.bin` (1.36), `N2PET50W.bin` (older) |
| entry1 (device) | d0c7e037-2060-4e3a-8345-2f07343ea8ac | 3725657469 | — |
| entry2 (device) | 552113b2-a4aa-455a-add6-b3e2d82dbc90 | 65548 | — |
| entry3 (battery) | 60df3168-7e6d-4417-9d6d-684ad0a3eec2 | 17039372 | `5B10W13884.cap` (260.12) |
| entry4 (device) | 872e3b42-9a57-4684-a29b-03a173c89115 | 117572096 | — |
| entry5 (camera) | 7c8c8f35-04f2-b6d2-bae5-ad4367c4016b | 29207 | `04F2-B6D2-7217-N2PET.bin` |
Future Lenovo capsules can be applied with fwupd's UEFI capsule plugin (e.g. `fwupdtool install-blob`)
— check LVFS first; untested here.
