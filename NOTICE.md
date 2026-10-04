# NOTICE — third-party components and attributions

This core is distributed under **GPL-3.0-or-later** (see `LICENSE`). It
includes the third-party components below. Each one keeps its original file
headers.

## Components compiled into the core

| Component | Author(s) | Licence | Location |
|---|---|---|---|
| MiSTer framework (`sys_top`, `hps_io`, `arcade_video`, `video_freak`, `ascal`, `osd`, …) | Till Harbaum, Alexey Melnikov (Sorgelig) and the MiSTer-devel contributors | GPL-2.0-or-later / GPL-3.0-or-later (per-file headers) | `sys/`: vendored verbatim from Template_MiSTer (commit 3ea1134, 2026-08-26), never edited. 57 files; SHA-256 of all file contents concatenated in path order (`find . -type f \| LC_ALL=C sort \| xargs cat \| sha256sum`): `52714fdcc2a6f2b00dd53298da31f5fabc5dbf8741f00ca246ab903fa92eaa2d` |
| **fx68k**, a cycle-exact MC68000 with its microcode ROMs | Jorge Cwik (ijor) | GPL-3.0-or-later | `rtl/lib/fx68k/`: vendored verbatim, with its own `LICENSE` and `README.md` |
| **IKAOPLL**, the YM2413 FM synthesiser (modelled on the chip's die) | Sehyeon Kim (Raki); its README credits nukeykt's Nuked-SMS-FPGA for the 9-bit output design | BSD-2-Clause | `rtl/lib/ikaopll/`: `src/IKAOPLL.v` and `src/IKAOPLL_modules/*.v` vendored verbatim from github.com/ika-musume/IKAOPLL commit `4d393238d1be33ea428a454956270504f037dfa3`, with its `LICENSE` and `README.md` |
| **`klax_oki6295.v`**, an MSM6295 ADPCM core | the Klax MiSTer core authors | GPL-2.0-or-later | `rtl/lib/oki/`: vendored verbatim |
| `analog_hsize.sv`, the analog-VGA horizontal stretch | Umberto Parisi (rmonic79), from Arcade-Raiden_MiSTer | GPL-3.0-or-later | `rtl/video/analog_hsize.sv`: vendored by way of the Toobin' and Xybots cores, with two small changes listed in its header (a buffer-size parameter, no RAM init loop) |
| Intel PLL megafunction (50 MHz → 57.272727 MHz) | Intel Corporation (generated IP) | Intel FPGA IP licence, as generated | `rtl/pll.v`, `rtl/pll/` |

All of these licences are compatible with distributing the combined work
under GPL-3.0-or-later.

## Code adapted from sibling Atari cores

The project structure, build files and the board-independent modules come
from the Batman and Skull & Crossbones MiSTer cores (GPL-3.0). Those in turn
build on the Klax, Bad Lands, Vindicators, Xybots, Toobin' and Blasteroids
cores. Each adapted file keeps its original copyright header and names the
file it came from.

- Build and glue: `Arcade-Rampart.sv`, `Rampart.qsf`, `Rampart.sdc`,
  `files.qip`, `clean.bat`
- SDRAM and ROM loading: `rampart_sdram.sv`, `rampart_sdram_loader.sv`,
  `rampart_rom_loader.sv`, `rampart_nvram_io.sv`
- Clocking and video output: `rampart_clocks.sv`, `rampart_analog_adjust.sv`
- Main CPU board:
  - `rampart_cpu.sv` (from Skull & Crossbones)
  - `rampart_eeprom.sv` (from Batman)
  - `rampart_leta.sv`, a new implementation. Its structure comes from the
    Blasteroids core. Its behaviour follows the documented operation of
    JROK's LETA replacement (`leta_rep.vhd`, published as freeware and
    carried in the Atari System 1 MiSTer core); none of that code is copied.
- Cabinet controls: `rampart_tball_axis.sv` and `rampart_controls.sv` take
  their pacing and sensitivity scheme from the Blasteroids core's
  `blstroid_whirly.sv`.
- Video:
  - `rampart_sos2.sv` (counter structure from Skull & Crossbones'
    `skullxbo_sos2_sync.sv`)
  - `rampart_lb.sv` (from Batman's `batman_lb.sv`)
  - `rampart_dac.sv` (from Batman's `batman_dac.sv`)
  - `rampart_cram.sv` (shape from Klax's `klax_palette.v`)
  - The motion-object engine `rampart_mob.sv` combines the Skull &
    Crossbones transcription of the Atari MOB 137593-001
    (`skullxbo_mob.sv`) with the Klax core's motion-object arithmetic
    (`klax_motion_objects.v`). The Klax core is GPL-2.0-or-later,
    https://github.com/MiSTer-devel/Arcade-Klax_MiSTer, commit `7b30962`.
- Sound:
  - `rampart_oki.sv` is adapted from the Batman core's `batman_oki.sv`,
    which wraps the Klax core's `klax_oki6295.v` (GPL-2.0-or-later). It adds
    a per-sample voice snapshot so commands land on the same sample
    whatever the ROM latency.
  - `rampart_ym.sv` is a new wrapper around IKAOPLL: it holds the bus
    write to an XIN edge and sums the chip's two DAC pins per slot.
  - `rampart_snd_filter.sv` is a new implementation of this board's audio
    filters. Its one-section-per-RC-stage layout follows the sound filters
    of the Skull & Crossbones and Batman cores.
- Slapstic: `rampart_slapstic.sv` keeps the structure of the Xybots core's
  `xybots_slapstic.sv`; its state machine follows MAME's `slapstic.cpp`
  (BSD-3-Clause) as a functional reference.

## Reference material

MAME (BSD-3-Clause; Aaron Giles and the MAME contributors) served as a
functional reference and for comparison captures. No MAME source is compiled
into this core.

## Trademarks and content

This repository contains no ROM data, no artwork, no schematics and no PLD
fuse dumps. *Rampart* is a trademark of its respective owner. This is an
unaffiliated hardware-preservation project. Use it only with ROMs you are
legally entitled to.
