# Emuladores que acepta ES-DE y cómo los recibe Orbital

Generado a partir de los archivos de ES-DE 3 (`resources/systems/windows/es_systems.xml` y `es_find_rules.xml`) el
2026-10-16. ES-DE conoce **195 sistemas** y **124 emuladores** (RetroArch con sus núcleos + 123 programas propios).

## Cómo los recibe Orbital

1. **Lista propia (afinada)** — `orbital/library/detect.py · KNOWN`: 12 sistemas con argumentos pensados para la TV
   (pantalla completa, sin menús) y detección en Descargas, Escritorio, `C:\Emuladores`, etc. Manda siempre.
2. **Reglas de ES-DE (todo lo demás)** — `orbital/library/esde_systems.py`: para cada sistema que tengas en `ROMs/`
   y Orbital no conozca, lee los comandos y reglas de búsqueda de ES-DE (los de fábrica y los tuyos de
   `ES-DE/custom_systems/`, que mandan), toma el primero instalado (con RetroArch, solo si el núcleo existe) y deja los
   demás como alternativos. El emulador elegido para el sistema en ES-DE va primero. Así, poner un emulador donde ES-DE
   lo busca y juegos en `ROMs/<sistema>` basta para que salga en Orbital.
3. **Accesos directos** (`.lnk`, «Shortcut» en ES-DE): Orbital los abre por su cuenta.

### Lo que todavía no se arma solo
- Comandos con `%INJECT%` o `%RPCS3_GAMEID%` (RPCS3 y shadPS4 por número de serie): se usa el siguiente comando del
  sistema si lo hay (p. ej. RPCS3 por carpeta o ISO).
- Juegos que son **carpetas** (`.ps3`, `.ps4`): PS4 ya tiene soporte propio (`library/ps4.py`); PS3 sería el siguiente.
- Comandos por la consola de Windows (`%EMULATOR_OS-SHELL%`): son puertos nativos y scripts; los `.lnk` sí se abren.

## Resumen
- Afinados por Orbital: **12**
- Reconocidos con las reglas de ES-DE: **166**
- Steam: propio de Orbital (lee tu biblioteca de Steam directo)
- Sin un emulador que Orbital sepa abrir: **16** (motores de juego, Android, Kodi, Xbox One, PS Vita, Windows y tiendas de PC, que en ES-DE van por accesos directos)

## Todos los sistemas

| Sistema | Carpeta | Emuladores propios | Núcleos de RetroArch | En Orbital |
|---|---|---|---|---|
| 3DO Interactive Multiplayer | `3do` | — | 1 | Sí, con las reglas de ES-DE |
| Acorn Archimedes | `archimedes` | MAME [Model A440/1], MAME [Model A3000], MAME [Model A310], MAME [Model A540] | — | Sí, con las reglas de ES-DE |
| Acorn Computers BBC Micro | `bbcmicro` | MAME | 1 | Sí, con las reglas de ES-DE |
| Acorn Electron | `electron` | MAME [Tape], MAME [Diskette DFS], MAME [Diskette ADFS] | — | Sí, con las reglas de ES-DE |
| Adobe Flash | `flash` | Ruffle, ArcadeFlashWeb | — | Sí, con las reglas de ES-DE |
| AdvanceMAME | `mame-advmame` | AdvanceMAME | — | Sí, con las reglas de ES-DE |
| Adventure Game Studio Game Engine | `ags` | — | — | No todavía |
| Amstrad CPC | `amstradcpc` | CPCemu, MAME | 2 | Sí, con las reglas de ES-DE |
| Amstrad GX4000 | `gx4000` | MAME | 2 | Sí, con las reglas de ES-DE |
| Android Apps | `androidapps` | — | — | No todavía |
| Android Games | `androidgames` | — | — | No todavía |
| Apple II | `apple2` | AppleWin, Mednafen, MAME, izapple2 | 2 | Sí, con las reglas de ES-DE |
| Apple IIGS | `apple2gs` | MAME, MAME [Software list] | 2 | Sí, con las reglas de ES-DE |
| Apple Macintosh | `macintosh` | MAME Mac SE Bootable, MAME Mac SE Boot Disk, MAME Mac Plus Bootable, MAME Mac Plus Boot Disk, Basilisk II, SheepShaver | 1 | Sí, con las reglas de ES-DE |
| Arcade | `arcade` | MAME, GroovyMAME, FinalBurn Neo, Flycast, Flycast Dojo, Model 2 Emulator, Model 2 Emulator [Suspend ES-DE], PCSX2x6, MFME, ArcadeDuck | 13 | Sí, con las reglas de ES-DE |
| Arduboy Miniature Game System | `arduboy` | — | 2 | Sí, con las reglas de ES-DE |
| Atari 2600 | `atari2600` | Stella, Gopher2600, ares | 4 | Sí, con las reglas de ES-DE |
| Atari 5200 | `atari5200` | Atari800 | 2 | Sí, con las reglas de ES-DE |
| Atari 7800 ProSystem | `atari7800` | MAME | 2 | Sí, con las reglas de ES-DE |
| Atari 800 | `atari800` | Atari800 | 1 | Sí, con las reglas de ES-DE |
| Atari Jaguar | `atarijaguar` | BigPEmu, MAME | 1 | Sí, con las reglas de ES-DE |
| Atari Jaguar CD | `atarijaguarcd` | BigPEmu | 1 | Sí, con las reglas de ES-DE |
| Atari Lynx | `atarilynx` | Mednafen | 4 | Sí, con las reglas de ES-DE |
| Atari ST | `atarist` | Hatari | 2 | Sí, con las reglas de ES-DE |
| Atari XE | `atarixe` | Atari800 | 1 | Sí, con las reglas de ES-DE |
| Bally Astrocade | `astrocde` | MAME | 1 | Sí, con las reglas de ES-DE |
| Bandai SuFami Turbo | `sufami` | Snes9x, bsnes, ares | 7 | Sí, con las reglas de ES-DE |
| Bandai WonderSwan | `wonderswan` | Mednafen, ares, ares [Benesse Pocket Challenge V2], Mesen | 2 | Sí, con las reglas de ES-DE |
| Bandai WonderSwan Color | `wonderswancolor` | Mednafen, ares, Mesen | 2 | Sí, con las reglas de ES-DE |
| Bit Corporation Gamate | `gamate` | MAME | 1 | Sí, con las reglas de ES-DE |
| Capcom Play System | `cps` | MAME, FinalBurn Neo | 10 | Sí, con las reglas de ES-DE |
| Capcom Play System I | `cps1` | MAME, FinalBurn Neo | 8 | Sí, con las reglas de ES-DE |
| Capcom Play System II | `cps2` | MAME, FinalBurn Neo | 8 | Sí, con las reglas de ES-DE |
| Capcom Play System III | `cps3` | MAME, FinalBurn Neo | 8 | Sí, con las reglas de ES-DE |
| Casio PV-1000 | `pv1000` | MAME | 1 | Sí, con las reglas de ES-DE |
| ChaiLove Game Engine | `chailove` | — | 1 | Sí, con las reglas de ES-DE |
| Coleco Adam | `adam` | MAME [Diskette], MAME [Tape], MAME [Cartridge], MAME [Software list] | — | Sí, con las reglas de ES-DE |
| Coleco ColecoVision | `colecovision` | BlastEm, ares, Mesen | 4 | Sí, con las reglas de ES-DE |
| Commodore 64 | `c64` | VICE x64sc Accurate | 5 | Sí, con las reglas de ES-DE |
| Commodore Amiga | `amiga` | FS-UAE | 3 | Sí, con las reglas de ES-DE |
| Commodore Amiga 1200 | `amiga1200` | FS-UAE | 3 | Sí, con las reglas de ES-DE |
| Commodore Amiga 600 | `amiga600` | FS-UAE | 3 | Sí, con las reglas de ES-DE |
| Commodore Amiga CD32 | `amigacd32` | FS-UAE | 3 | Sí, con las reglas de ES-DE |
| Commodore CDTV | `cdtv` | FS-UAE | 3 | Sí, con las reglas de ES-DE |
| Commodore Plus/4 | `plus4` | VICE xplus4 | 1 | Sí, con las reglas de ES-DE |
| Commodore VIC-20 | `vic20` | VICE xvic | 1 | Sí, con las reglas de ES-DE |
| Console Arcade Systems | `consolearcade` | MAME, Flycast, Flycast Dojo, Mednafen [Sega Saturn], PCSX2x6, RPCS3 ISO, Dolphin, Triforce, xemu, Cxbx-Reloaded, ArcadeDuck | 4 | Sí, con las reglas de ES-DE |
| Creatronic Mega Duck | `megaduck` | MAME | 2 | Sí, con las reglas de ES-DE |
| Daphne Arcade LaserDisc Emulator | `daphne` | MAME, ares [Mega LD] | 2 | Sí, con las reglas de ES-DE |
| Desktop Applications | `desktop` | — | — | No todavía |
| Doom | `doom` | PrBoom+ | 3 | Sí, con las reglas de ES-DE |
| DOS (PC) | `dos` | DOSBox Pure Unleashed, DOSBox-X, DOSBox Staging, DREAMM | 4 | Sí, con las reglas de ES-DE |
| Dragon Data Dragon 32 | `dragon32` | MAME Dragon 32 [Tape], MAME Dragon 32 [Cartridge], MAME Dragon 64 [Tape], MAME Dragon 64 [Cartridge], XRoar Dragon 32, XRoar Dragon 64 | — | Sí, con las reglas de ES-DE |
| EasyRPG Game Engine | `easyrpg` | EasyRPG Player | 1 | Sí, con las reglas de ES-DE |
| Emerson Arcadia 2001 | `arcadia` | MAME, WinArcadia | 2 | Sí, con las reglas de ES-DE |
| Emulators | `emulators` | — | — | No todavía |
| Epic Games Store | `epic` | — | — | No todavía |
| Epoch Super Cassette Vision | `scv` | MAME | 1 | Sí, con las reglas de ES-DE |
| Fairchild Channel F | `channelf` | MAME | 2 | Sí, con las reglas de ES-DE |
| FinalBurn Alpha | `fba` | — | 5 | Sí, con las reglas de ES-DE |
| FinalBurn Neo | `fbneo` | FinalBurn Neo | 1 | Sí, con las reglas de ES-DE |
| Fujitsu FM Towns | `fmtowns` | MAME | 1 | Sí, con las reglas de ES-DE |
| Fujitsu FM-7 | `fm7` | MAME [FM-7 Diskette], MAME [FM-7 Tape], MAME [FM-7 Software list], MAME [FM77AV Diskette], MAME [FM77AV Tape], MAME [FM77AV Software list] | — | Sí, con las reglas de ES-DE |
| Funtech Super A'Can | `supracan` | MAME | 1 | Sí, con las reglas de ES-DE |
| Future Pinball | `fpinball` | Future Pinball, Future Pinball FPLoader | — | Sí, con las reglas de ES-DE |
| GCE Vectrex | `vectrex` | MAME | 2 | Sí, con las reglas de ES-DE |
| Google Android | `android` | — | — | No todavía |
| Hartung Game Master | `gmaster` | MAME | 1 | Sí, con las reglas de ES-DE |
| IBM PC | `pc` | DOSBox Pure Unleashed, DOSBox-X, DOSBox Staging, DREAMM | 4 | Sí, con las reglas de ES-DE |
| Infocom Z-machine | `zmachine` | Gargoyle | 1 | Sí, con las reglas de ES-DE |
| Java 2 Micro Edition (J2ME) | `j2me` | KEmulator | 1 | Sí, con las reglas de ES-DE |
| Kodi Home Theatre Software | `kodi` | — | — | No todavía |
| LaserDisc Games | `laserdisc` | MAME, ares [Mega LD] | 2 | Sí, con las reglas de ES-DE |
| LCD Handheld Games | `lcdgames` | MAME Local Artwork, MAME | 2 | Sí, con las reglas de ES-DE |
| LowRes NX Fantasy Console | `lowresnx` | — | 1 | Sí, con las reglas de ES-DE |
| Lutris Open Gaming Platform | `lutris` | — | — | No todavía |
| Lutro Game Engine | `lutro` | — | 1 | Sí, con las reglas de ES-DE |
| M.U.G.E.N Game Engine | `mugen` | — | — | No todavía |
| Magnavox Odyssey 2 | `odyssey2` | MAME | 2 | Sí, con las reglas de ES-DE |
| Mattel Electronics Intellivision | `intellivision` | MAME | 2 | Sí, con las reglas de ES-DE |
| MGT SAM Coupé | `samcoupe` | SimCoupé | — | Sí, con las reglas de ES-DE |
| Microsoft Windows | `windows` | — | — | No todavía |
| Microsoft Windows 3.x | `windows3x` | DOSBox-X, DOSBox Pure Unleashed | 1 | Sí, con las reglas de ES-DE |
| Microsoft Windows 9x | `windows9x` | DOSBox-X, DOSBox Pure Unleashed | 1 | Sí, con las reglas de ES-DE |
| Microsoft Xbox | `xbox` | xemu, Cxbx-Reloaded | — | Afinado (lista propia de Orbital) |
| Microsoft Xbox 360 | `xbox360` | — | — | Afinado (lista propia de Orbital) |
| Microsoft Xbox One | `xboxone` | — | — | No todavía |
| MSX | `msx` | ares, Emulicious | 2 | Sí, con las reglas de ES-DE |
| MSX Turbo R | `msxturbor` | — | 1 | Sí, con las reglas de ES-DE |
| MSX1 | `msx1` | ares, Emulicious | 2 | Sí, con las reglas de ES-DE |
| MSX2 | `msx2` | ares, Emulicious | 2 | Sí, con las reglas de ES-DE |
| Multi Emulator Super System | `mess` | — | 1 | Sí, con las reglas de ES-DE |
| Multiple Arcade Machine Emulator | `mame` | MAME, GroovyMAME, FinalBurn Neo, Flycast, Flycast Dojo, Model 2 Emulator, Model 2 Emulator [Suspend ES-DE], PCSX2x6, MFME, ArcadeDuck | 13 | Sí, con las reglas de ES-DE |
| Namco-Sega-Nintendo Triforce | `triforce` | Dolphin, Triforce | 1 | Sí, con las reglas de ES-DE |
| NEC PC Engine | `pcengine` | Geargrafx, Mednafen, Mesen, ares | 5 | Sí, con las reglas de ES-DE |
| NEC PC Engine CD | `pcenginecd` | Geargrafx, Mednafen, Mesen, ares | 5 | Sí, con las reglas de ES-DE |
| NEC PC-8800 Series | `pc88` | QUASI88 | 1 | Sí, con las reglas de ES-DE |
| NEC PC-9800 Series | `pc98` | — | 2 | Sí, con las reglas de ES-DE |
| NEC PC-FX | `pcfx` | Mednafen | 1 | Sí, con las reglas de ES-DE |
| NEC SuperGrafx | `supergrafx` | Geargrafx, Mednafen, Mesen, ares | 4 | Sí, con las reglas de ES-DE |
| NEC TurboGrafx-16 | `tg16` | Geargrafx, Mednafen, Mesen, ares | 5 | Sí, con las reglas de ES-DE |
| NEC TurboGrafx-CD | `tg-cd` | Geargrafx, Mednafen, Mesen, ares | 5 | Sí, con las reglas de ES-DE |
| Nintendo 3DS | `n3ds` | Azahar, AzaharPlus, Citra, Mandarine, Lime3DS, Panda3DS | 3 | Sí, con las reglas de ES-DE |
| Nintendo 64 | `n64` | Mupen64Plus, Parallel Launcher, simple64, Rosalie's Mupen GUI, Project64, ares, Gopher64 | 2 | Sí, con las reglas de ES-DE |
| Nintendo 64DD | `n64dd` | Rosalie's Mupen GUI, ares | 2 | Sí, con las reglas de ES-DE |
| Nintendo DS | `nds` | melonDS, NooDS, SkyEmu | 6 | Afinado (lista propia de Orbital) |
| Nintendo Entertainment System | `nes` | Mesen, puNES, Mednafen, ares, ares FDS, jgenesis | 6 | Sí, con las reglas de ES-DE |
| Nintendo Famicom Disk System | `fds` | Mesen, Mednafen, ares | 5 | Sí, con las reglas de ES-DE |
| Nintendo Family Computer | `famicom` | Mesen, puNES, Mednafen, ares, ares FDS, jgenesis | 6 | Sí, con las reglas de ES-DE |
| Nintendo Game and Watch | `gameandwatch` | MAME Local Artwork, MAME | 2 | Sí, con las reglas de ES-DE |
| Nintendo Game Boy | `gb` | SameBoy, Gearboy, Mesen, mGBA, VBA-M, SkyEmu, Mednafen, ares, jgenesis, Emulicious | 12 | Sí, con las reglas de ES-DE |
| Nintendo Game Boy Advance | `gba` | mGBA, VBA-M, NooDS, SkyEmu, Mednafen, ares, Mesen | 7 | Afinado (lista propia de Orbital) |
| Nintendo Game Boy Color | `gbc` | SameBoy, Gearboy, Mesen, mGBA, VBA-M, SkyEmu, Mednafen, ares, jgenesis, Emulicious | 12 | Sí, con las reglas de ES-DE |
| Nintendo GameCube | `gc` | Dolphin, PrimeHack, Triforce | 1 | Afinado (lista propia de Orbital) |
| Nintendo Pokémon Mini | `pokemini` | — | 1 | Sí, con las reglas de ES-DE |
| Nintendo Satellaview | `satellaview` | Snes9x, bsnes, Mesen, ares | 9 | Sí, con las reglas de ES-DE |
| Nintendo SFC (Super Famicom) | `sfc` | Snes9x, bsnes, Mesen, Mednafen, ares, jgenesis, SUPER ZSNES | 10 | Sí, con las reglas de ES-DE |
| Nintendo SNES (Super Nintendo) | `snes` | Snes9x, bsnes, Mesen, Mednafen, ares, jgenesis, SUPER ZSNES | 10 | Sí, con las reglas de ES-DE |
| Nintendo SNES (Super Nintendo) | `snesna` | Snes9x, bsnes, Mesen, Mednafen, ares, jgenesis, SUPER ZSNES | 10 | Sí, con las reglas de ES-DE |
| Nintendo Super Game Boy | `sgb` | Mesen, mGBA | 4 | Sí, con las reglas de ES-DE |
| Nintendo Switch | `switch` | Eden, Ryujinx | — | Afinado (lista propia de Orbital) |
| Nintendo Virtual Boy | `virtualboy` | Mednafen | 1 | Sí, con las reglas de ES-DE |
| Nintendo Wii | `wii` | Dolphin, PrimeHack | 1 | Afinado (lista propia de Orbital) |
| Nintendo Wii U | `wiiu` | Cemu | 1 | Afinado (lista propia de Orbital) |
| Nokia N-Gage | `ngage` | EKA2L1 [Mounted], EKA2L1 [Installed] | — | Sí, con las reglas de ES-DE |
| OpenBOR Game Engine | `openbor` | — | — | No todavía |
| Othello Multivision | `multivision` | Mesen | 1 | Sí, con las reglas de ES-DE |
| Palm OS | `palm` | — | 1 | Sí, con las reglas de ES-DE |
| PC Arcade Systems | `pcarcade` | — | — | No todavía |
| Philips CD-i | `cdimono1` | MAME | 2 | Sí, con las reglas de ES-DE |
| Philips Videopac G7000 | `videopac` | MAME | 2 | Sí, con las reglas de ES-DE |
| PICO-8 Fantasy Console | `pico8` | PICO-8, PICO-8 Splore | 1 | Sí, con las reglas de ES-DE |
| Ports | `ports` | — | 8 | Sí, con las reglas de ES-DE |
| Quake | `quake` | — | 6 | Sí, con las reglas de ES-DE |
| Sammy Corporation Atomiswave | `atomiswave` | Flycast, Flycast Dojo, Demul | 1 | Sí, con las reglas de ES-DE |
| ScummVM Game Engine | `scummvm` | ScummVM, DREAMM | 1 | Sí, con las reglas de ES-DE |
| Sega CD | `segacd` | BlastEm, ares, jgenesis | 5 | Sí, con las reglas de ES-DE |
| Sega Dreamcast | `dreamcast` | Flycast, Flycast Dojo, Redream, Demul | 1 | Sí, con las reglas de ES-DE |
| Sega Game Gear | `gamegear` | BlastEm, Mednafen, Mesen, ares, jgenesis, Emulicious | 7 | Sí, con las reglas de ES-DE |
| Sega Genesis | `genesis` | BlastEm, Mednafen, ares, jgenesis | 5 | Sí, con las reglas de ES-DE |
| Sega Genesis 32X | `sega32xna` | BlastEm, ares | 2 | Sí, con las reglas de ES-DE |
| Sega Mark III | `mark3` | BlastEm, Mednafen, Mesen, ares, jgenesis, Emulicious | 7 | Sí, con las reglas de ES-DE |
| Sega Master System | `mastersystem` | BlastEm, Mednafen, Mesen, ares, jgenesis, Emulicious | 7 | Sí, con las reglas de ES-DE |
| Sega Mega Drive | `megadrive` | BlastEm, Mednafen, ares, jgenesis | 5 | Sí, con las reglas de ES-DE |
| Sega Mega Drive | `megadrivejp` | BlastEm, Mednafen, ares, jgenesis | 5 | Sí, con las reglas de ES-DE |
| Sega Mega Drive 32X | `sega32x` | BlastEm, ares | 2 | Sí, con las reglas de ES-DE |
| Sega Mega-CD | `megacd` | BlastEm, ares, jgenesis | 5 | Sí, con las reglas de ES-DE |
| Sega Mega-CD | `megacdjp` | BlastEm, ares, jgenesis | 5 | Sí, con las reglas de ES-DE |
| Sega Model 2 | `model2` | MAME, Model 2 Emulator, Model 2 Emulator [Suspend ES-DE] | 1 | Sí, con las reglas de ES-DE |
| Sega Model 3 | `model3` | MAME | 2 | Sí, con las reglas de ES-DE |
| Sega NAOMI | `naomi` | Flycast, Flycast Dojo, Demul | 1 | Sí, con las reglas de ES-DE |
| Sega NAOMI 2 | `naomi2` | Flycast, Flycast Dojo, Demul | 1 | Sí, con las reglas de ES-DE |
| Sega NAOMI GD-ROM | `naomigd` | Flycast, Flycast Dojo | 1 | Sí, con las reglas de ES-DE |
| Sega Saturn | `saturn` | Kronos, Yaba Sanshiro 2, Ymir, Mednafen, SSF | 4 | Sí, con las reglas de ES-DE |
| Sega Saturn | `saturnjp` | Kronos, Yaba Sanshiro 2, Ymir, Mednafen, SSF | 4 | Sí, con las reglas de ES-DE |
| Sega SG-1000 | `sg-1000` | BlastEm, Mesen, ares | 5 | Sí, con las reglas de ES-DE |
| Sega Super 32X | `sega32xjp` | BlastEm, ares | 2 | Sí, con las reglas de ES-DE |
| Sega Titan Video Game System | `stv` | MAME, Mednafen | 2 | Sí, con las reglas de ES-DE |
| Sharp X1 | `x1` | MAME [Diskette], MAME [Tape] | 1 | Sí, con las reglas de ES-DE |
| Sharp X68000 | `x68000` | MAME, XM6 Pro-68k, XM6 TypeG | 1 | Sí, con las reglas de ES-DE |
| Sinclair ZX Spectrum | `zxspectrum` | Fuse | 1 | Sí, con las reglas de ES-DE |
| Sinclair ZX Spectrum Next | `zxnext` | #CSpect, ZEsarUX | — | Sí, con las reglas de ES-DE |
| Sinclair ZX81 | `zx81` | — | 1 | Sí, con las reglas de ES-DE |
| SNK Neo Geo | `neogeo` | FinalBurn Neo, MAME | 3 | Sí, con las reglas de ES-DE |
| SNK Neo Geo CD | `neogeocd` | FinalBurn Neo, MAME | 3 | Sí, con las reglas de ES-DE |
| SNK Neo Geo CD | `neogeocdjp` | FinalBurn Neo, MAME | 3 | Sí, con las reglas de ES-DE |
| SNK Neo Geo Pocket | `ngp` | Mednafen, ares | 2 | Sí, con las reglas de ES-DE |
| SNK Neo Geo Pocket Color | `ngpc` | Mednafen, ares | 2 | Sí, con las reglas de ES-DE |
| Solarus Game Engine | `solarus` | Solarus | — | Sí, con las reglas de ES-DE |
| Sony PlayStation | `psx` | DuckStation, ares, Mednafen | 4 | Afinado (lista propia de Orbital) |
| Sony PlayStation 2 | `ps2` | PCSX2, PCSX2 Legacy | 3 | Afinado (lista propia de Orbital) |
| Sony PlayStation 3 | `ps3` | RPCS3 Directory, RPCS3 ISO | — | Sí, con las reglas de ES-DE |
| Sony PlayStation 4 | `ps4` | shadPS4 eboot.bin, shadPS4 [GUI] eboot.bin | — | Afinado (lista propia de Orbital) |
| Sony PlayStation Portable | `psp` | PPSSPP | 1 | Afinado (lista propia de Orbital) |
| Sony PlayStation Vita | `psvita` | — | — | No todavía |
| Spectravideo | `spectravideo` | — | 1 | Sí, con las reglas de ES-DE |
| Symbian | `symbian` | EKA2L1 [Nokia N-Gage], EKA2L1 [Nokia N70], EKA2L1 [Nokia N97] | — | Sí, con las reglas de ES-DE |
| Taito Type X | `type-x` | — | — | No todavía |
| Tandy Color Computer | `coco` | XRoar CoCo 2 NTSC, XRoar CoCo 2 PAL, MAME [Cartridge], MAME [Tape] | — | Sí, con las reglas de ES-DE |
| Tandy TRS-80 | `trs-80` | sdl2trs DOS Diskette, sdl2trs Bootable Diskette, sdl2trs CMD File | — | Sí, con las reglas de ES-DE |
| Tangerine Computer Systems Oric | `oric` | MAME, Oricutron | — | Sí, con las reglas de ES-DE |
| Tano Dragon | `tanodragon` | MAME [Tape], MAME [Cartridge], XRoar | — | Sí, con las reglas de ES-DE |
| Texas Instruments TI-99 | `ti99` | MAME, MAME Legacy | — | Sí, con las reglas de ES-DE |
| Thomson MO/TO Series | `moto` | — | 1 | Sí, con las reglas de ES-DE |
| Thomson TO8 | `to8` | — | 1 | Sí, con las reglas de ES-DE |
| TIC-80 Fantasy Computer | `tic80` | TIC-80 | 1 | Sí, con las reglas de ES-DE |
| Tiger Electronics Game.com | `gamecom` | MAME | 1 | Sí, con las reglas de ES-DE |
| Uzebox Open Source Console | `uzebox` | — | 1 | Sí, con las reglas de ES-DE |
| Valve Steam | `steam` | — | — | Propio de Orbital (lee Steam directo) |
| Vircon32 Virtual Console | `vircon32` | Vircon32 | 1 | Sí, con las reglas de ES-DE |
| Visual Pinball | `vpinball` | Visual Pinball | — | Sí, con las reglas de ES-DE |
| VTech CreatiVision | `crvision` | MAME | 2 | Sí, con las reglas de ES-DE |
| VTech V.Smile | `vsmile` | MAME | 1 | Sí, con las reglas de ES-DE |
| WASM-4 Fantasy Console | `wasm4` | — | 1 | Sí, con las reglas de ES-DE |
| Watara Supervision | `supervision` | MAME | 2 | Sí, con las reglas de ES-DE |
