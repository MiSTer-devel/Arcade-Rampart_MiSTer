# Rampart (Atari Games, 1990) for MiSTer

An FPGA recreation of the Atari Games arcade board for **Rampart** (1990),
for the [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki)
platform. In Rampart up to three players repair castle walls with
puzzle-shaped pieces, place cannons and fire on each other's castles.

The core rebuilds the board (Atari 136082) rather than emulating the game:
an MC68000 at 7.16 MHz, the SLAPSTIC 137412-118 bank switcher, a
512 x 256 x 8 bitmap playfield, the MOB 137593-001 motion-object processor
and line buffer, the address-decode and video GALs, the LETA trackball
counters, the 2816 EEPROM, and YM2413 + MSM6295 sound with the board's
analogue mixer and filters.

The address decoding and the video timing are transcribed from the board's
own GAL chips, and the inputs, reset and watchdog, sync, colour output and
sound circuits follow the schematics in Atari's operator manuals. Atari never
published the pages for the CPU, the video RAMs and the custom chips, so
MAME's Rampart driver filled those gaps. Where the board and MAME differ,
the core follows the board; the differences you may notice are listed below.

Author: RetroShrimp. Licence: GPL-3.0-or-later.

## Supported sets

| MRA | MAME set | Controls | Players |
| --- | --- | --- | --- |
| `Rampart.mra` | `rampart` | three trackballs | 3 |
| `Rampart (Joystick, bigger ROMs).mra` | `rampart2p` | 4-way joysticks | 2 or 3 |
| `Rampart (Joystick, smaller ROMs).mra` | `rampart2pa` | 4-way joysticks | 2 or 3 |
| `Rampart (Japan, Joystick).mra` | `rampartj` | 4-way joysticks, start buttons | 2 or 3 |

The sets differ in their control panel and program-ROM layout, and so in
the address-decode GAL fitted at 12C. Each MRA tells the core which board it
is.

## Installing

The core needs a MiSTer SDRAM module (32 MB or larger): the program and
sample ROMs are read from it while the game runs.

1. Copy `releases/Rampart_YYYYMMDD.rbf` to `_Arcade/cores/` on the SD card.
2. Copy `releases/Rampart.mra` to `_Arcade/` and the
   `releases/_alternatives/_Rampart/` folder to `_Arcade/_alternatives/`.
3. Put the ROM zips in `games/mame/` (see below).

## ROMs

No ROM data is included. The MRAs expect the **MAME 0.289** zips:
`rampart.zip`, and for the clones `rampart2p.zip`, `rampart2pa.zip` or
`rampartj.zip` together with the parent `rampart.zip`. Each MRA checks the
assembled image against an MD5, so a zip from a different MAME version may
be refused. The factory EEPROM image that MAME keeps in the set is used the
first time a set is run.

## Controls

The buttons are listed in the order MiSTer's input mapping asks for them:

| Button | On the board | Notes |
| --- | --- | --- |
| Fire | the player's FIRE button | also starts a game on the sets without start buttons |
| Rotate | the player's ROTATE button | |
| Coin | player 1: left coin chute, player 2: right chute, player 3: SERVICE (a service credit) | |
| Start | START 1 / START 2 | `rampartj` only; the other sets have no start button and do not ask for one |

The mouse's left and right buttons are player 1 Fire and Rotate.

### Trackballs (`rampart`)

Every source is added together, so nothing needs to be selected:

- **mouse**: player 1, both axes;
- **spinner**: players 1-3, X;
- **paddle**: players 1-3, X (the change in position);
- **left analog stick**: players 1-3, both axes, as a speed (full deflection
  is about 29 counts per frame);
- **d-pad**: players 1-3, the same speed as a full stick.

The motion is played out to the board's trackball counters at a steady rate
with a speed limit of about 60 counts per frame. The game reads each counter
as an 8-bit difference, so a faster mouse flick would otherwise wrap and
move the cursor backwards.

### Joysticks (`rampart2p`, `rampart2pa`, `rampartj`)

The cabinets have 4-way sticks. With the default `Joysticks: 4-way`, a
diagonal keeps the direction already held (or becomes the vertical one), so
the game never sees two directions at once. `8-way` passes the pad through
unchanged.

## OSD options

| Option | Values | Default | What it does |
| --- | --- | --- | --- |
| Aspect ratio, Orientation, Scale | | | the usual MiSTer video settings |
| Analog alignment | CRT H-Size / H-Position, VGA H-Shift / V-Shift | 0 | moves or stretches the analogue picture; the game timing is unchanged |
| Colour levels | Board DAC, MAME | Board DAC | see below |
| Trackball speed | 0.25x ... 4x | 1x | trackball set only |
| Trackball X / Y | Normal, Inverted | Normal | trackball set only |
| Joysticks | 4-way, 8-way | 4-way | joystick sets only |
| Players | 3, 2 | 3 | joystick sets only: the board's player-count strap |
| Service | Off, On | Off | the board's SELF TEST switch |
| Watchdog | Enabled, Disabled | Enabled | the board's watchdog-disable jumper; the game does not need it disabled |
| Reset | | | the board's reset |

### Colour levels (the DAC option)

`Board DAC` reproduces the board's colour output circuit: each gun is a
resistor ladder with a pull-up and a black clamp, so black is true black but
every lit level sits on a pedestal: the first step above black is about 16%
of full scale (3% in MAME), and the levels above it are compressed.
`MAME` uses MAME's plain linear scale instead. The game logic is identical
either way; only the output levels change.

## Settings, high scores and the service menu

Rampart has no DIP switches. Coinage, difficulty, statistics and high scores
live in the board's 2816 EEPROM, which the core saves through MiSTer's NVRAM
support (a 2 KB `.nvm` file in the `nvram` folder). A save is written about
1.2 seconds after the game's last EEPROM write, so a whole page of
option changes produces one save. With no save file, or a blank one, the
factory image from the ROM set is used. To return to factory settings,
delete the `.nvm` file.

The settings are changed in the game's own service menu:

1. Set `Service` to `On` in the OSD, then choose `Reset`.
2. The SELECT TEST menu appears. It uses the centre player's controls, which
   are **player 2**: Rotate moves the highlight and Fire opens the
   highlighted entry.
3. To leave, set `Service` back to `Off` and choose `Reset`.

## Differences from MAME you may notice

- **Colours.** With `Board DAC`, colours follow the board's resistor
  network: dark colours are brighter and contrast is lower than with MAME's
  linear palette. Choose `MAME` to match MAME.
- **Sound.** The board's analogue stage is modelled: output filters, the
  coupling capacitors, the resistor level switches for each chip and the
  final mixer. The sound is therefore softer at the top end than MAME's
  unfiltered mix. When the game lowers the ADPCM level, the board attenuates
  it rather than muting it as MAME does.
- **Mid-frame changes.** The picture is drawn line by line as the beam
  passes, as on the board. MAME draws the picture in four bands, so a change
  made mid-frame can appear a few lines lower, or a frame later, in MAME than
  on the board.
- **Resets.** The SLAPSTIC has no reset pin, so a watchdog or OSD reset
  leaves its bank alone, and the sound chips stay silent while the game
  holds their reset lines. MAME resets the SLAPSTIC on every reset.
- **Frame interrupt.** Rampart's interrupt circuit is not on any published
  drawing. The core uses the one Atari drew for the closely related Klax
  board, which interrupts at lines 64, 128 and 192 and at the start of
  vertical blank (line 240); MAME interrupts at lines 0, 64, 128, 192 and
  256. With the Klax circuit the game's palette updates fall inside vertical
  blank, so they do not show on screen. Attract-mode and demo timing can
  differ from MAME by a frame or two; the game plays the same.
- **CPU timing.** The 68000 is a cycle-exact model of the real chip, so
  instruction timing can differ slightly from MAME's 68000.

## Open hardware questions

A few details are not on any published Atari drawing. The core uses the
best available choice, and reports from real boards are welcome:

- the frame-interrupt circuit (the core uses the Klax board's, see above);
- whether the board adds CPU wait states for its slower chips (the core, like
  MAME, adds none);
- where two motion objects overlap, which one is drawn on top (the core
  follows MAME: the later one in the list);
- the exact vertical sync position of the SOS-2 sync chip;
- the trackball counters' power-up value;
- the direction each trackball axis counts (the OSD can invert either axis).

## Building

Open `Arcade-Rampart.qpf` in Quartus Prime Lite 17.0.2 and compile the
`Rampart` revision (`quartus_sh --flow compile Arcade-Rampart -c Rampart`).
The bitstream is `output_files/Rampart.rbf`. Add source files through
`files.qip`, never the Quartus GUI. If a compile writes the expanded pin
list back into `Rampart.qsf`, restore the short form, which ends at
`source files.qip`.

## Credits

- Jorge Cwik (ijor): fx68k, the cycle-exact MC68000.
- Sehyeon Kim (Raki): IKAOPLL, the YM2413.
- The Klax MiSTer core authors: the MSM6295 core and parts of the
  motion-object logic.
- The Batman, Skull & Crossbones, Bad Lands, Vindicators, Xybots, Toobin'
  and Blasteroids MiSTer cores: the project structure, SDRAM, loaders and
  shared Atari board logic.
- JROK: pin names traced from a real board for the GAL chips, and the
  documented behaviour of his LETA replacement.
- Umberto Parisi (rmonic79): the analog H-Size resampler.
- Alexey Melnikov (Sorgelig) and the MiSTer-devel contributors: the MiSTer
  framework.
- The MAME team: the Rampart driver served as a functional reference, and
  the MAME sets preserve the GAL fuse maps the core's address decoding and
  video timing are built from.

## Licence

GPL-3.0-or-later. See `LICENSE`, and `NOTICE.md` for the third-party
components and their licences. *Rampart* is a trademark of its respective
owner; this is an unaffiliated preservation project. Use it only with ROMs
you are legally entitled to.
