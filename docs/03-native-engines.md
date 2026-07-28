# Native engine re-implementations (when Wine is the wrong tool)

Status as of 2026-07-20. Host: Apple Silicon (arm64), macOS 26.x.

Wine is not always the best route. Some older games have **open-source engine
re-implementations** that build natively for Apple Silicon: the original game
assets (maps, models, sounds, sprites) are reused as-is, only the executable is
replaced. When such an engine exists and is maintained, prefer it over Wine —
no Rosetta, no 32-on-64 translation, better performance and battery, and no
breakage when Wine or macOS updates.

**Decision rule for this project:** check for a native engine *first*; fall back
to a plain Wine prefix (`docs/01-install-wine.md`) or a Sikarugir wrapper
(`docs/02-install-alternatives.md`) only if none exists.

## Counter-Strike 1.6 → Xash3D FWGS (the project's chosen route)

Full per-game notes: [games/counter-strike/README.md](../games/counter-strike/README.md).

- **Engine:** [Xash3D FWGS](https://github.com/FWGS/xash3d-fwgs) — a clean-room
  GoldSrc engine, macOS arm64 builds under the `continuous` release tag.
- **Game logic:** [CS16Client](https://github.com/Velaron/cs16-client) — arm64
  `client`/`server` dylibs plus bundled YaPB bots for offline play.
- **Assets:** copied from a Windows CS 1.6 install (unpacked with
  `innoextract`), assembled at `~/Games/cs16`.
- **Launcher:** `games/counter-strike/run.sh`, or `make counter-strike`.
- **Bots:** the CZ bots built into ReGameDLL (`bot_add`, `bot_quota`), configured
  by `games/counter-strike/bots.cfg`; listen server only. Details in the game
  README.

### Why not Wine

GoldSrc crashes a few seconds after launch under **every** Wine variant tested
on this machine (2026-07-20) with:

```
err:seh:NtRaiseException Exception frame is not in stack limits
```

Tested and failed: wine-stable 11.0 (new WoW64) plain / `-windowed` / inside a
virtual desktop; Game Porting Toolkit 3.0 (CrossOver 32on64, which additionally
hits a `virtual.c` assertion); and two different game builds (a modded
nitro_api build and a clean WaRzOnE build).

Root cause: the engine switches to its own allocated stack and raises SEH
exceptions from it. True 32-bit Wine on Linux tolerates this; both macOS
32-on-64 mechanisms validate exception frames against the thread's original
stack limits and refuse to dispatch. This is not a configuration problem — it
cannot be worked around from the Wine side.

### Trade-offs accepted

- **Windows x86 mods do not load.** Metamod and AMX Mod X are Windows DLLs; the
  native arm64 engine cannot load them, so admin/stats plugins are lost. The
  WaRzOnE build's `liblist.gam` had to be repointed from
  `addons\metamod\dlls\metamod.dll` to `dlls\cs.dll` to make hosting work at
  all — see the game README's troubleshooting section.
- **Multiplayer compatibility.** Xash3D FWGS speaks GoldSrc protocol 48 well
  enough for most community servers, but servers with strict anti-cheat may
  reject non-GoldSrc clients. LAN play between Xash3D clients is fine.
- **Manual updates.** Re-download the engine and client archives and re-extract
  over `~/Games/cs16`; assets do not change.

## Other native engines worth checking before reaching for Wine

Not used in this project yet — listed so the option is not forgotten:

| Original | Native engine |
| --- | --- |
| Half-Life 1 / GoldSrc mods | Xash3D FWGS |
| Quake / Quake II / III | vkQuake, yquake2, ioquake3 |
| Morrowind | OpenMW |
| Doom / Heretic / Hexen | GZDoom, Chocolate Doom |
| Command & Conquer, Red Alert, Dune 2000 | OpenRA |
| RollerCoaster Tycoon 2 | OpenRCT2 |
| Transport Tycoon Deluxe | OpenTTD |

Most of these are in Homebrew (`brew install --cask ...` or a formula) and ship
arm64 binaries. They all still require the original game assets.

Games with no native engine — such as visual novels like *A Piece of Blue Glass
Moon* — stay on the Wine routes.
