# Counter-Strike 1.6 (standalone, native via Xash3D)

- **Runs via:** Xash3D FWGS engine, **native Apple Silicon arm64 — no Wine**
- **Install location:** `~/Games/cs16`
- **Client:** CS16Client (arm64)
- **Bots:** the CZ bots built into `dlls/cs_arm64.dylib` (ReGameDLL) — see
  [Bots](#bots); the bundled YaPB dylib is unused
- **Assets:** extracted from the user's CS 1.6 WaRzOnE installer
- **Fonts/locale:** none needed.

This is **the** route for CS 1.6 in this project (decided 2026-07-20). The
Steam/Sikarugir notes in `games/steam-counter-strike/` are no longer used for
this game and are kept only as a recipe for future Steam titles. General
rationale for preferring native engines: `docs/03-native-engines.md`.

## Requirements

An Apple Silicon (arm64) Mac running **macOS 26.0 or newer**. The floor comes
from the CS16Client binaries, not from the engine — measured on this install
2026-07-31 with `LC_BUILD_VERSION`:

| Component | Files | Minimum macOS |
| --- | --- | --- |
| Xash3D FWGS engine | `xash3d`, `libxash.dylib`, `libmenu.dylib` | 14.8 |
| CS16Client | `cstrike/cl_dlls/menu_arm64.dylib`, `cstrike/cl_dlls/client_arm64.dylib`, `cstrike/dlls/cs_arm64.dylib` | 26.0 |

Check the target machine, and re-check the binaries after replacing either half:

```sh
sw_vers -productVersion
otool -l ~/Games/cs16/cstrike/cl_dlls/menu_arm64.dylib | grep -A3 LC_BUILD_VERSION
```

On an older macOS the failure is easy to misread as a missing file: the engine
itself starts normally (it only needs 14.8), but `dlopen` refuses the CS16Client
menu library, so `gameui.hInstance` is never set and the game reports `native
object "MenuFactory" is unavailable`. Copying a working `~/Games/cs16` from a
newer Mac does not help — the deployment target travels with the binaries.

The fix is to raise the OS on that machine, or to build CS16Client from source
there (<https://github.com/Velaron/cs16-client>) so its deployment target follows
the local SDK.

Note that the engine half is downloaded from the **rolling `continuous` tag**
(see [Setup](#setup-how-gamescs16-was-assembled)), so a fresh download is not
necessarily the 14.8 build these numbers were taken from.

## Why not Wine (post-mortem, 2026-07-20)

Every Wine variant on this machine crashes the GoldSrc engine a few seconds
after launch with `err:seh:NtRaiseException Exception frame is not in stack
limits`:

- wine-stable 11.0 (new WoW64), plain and with `-windowed`, and inside a
  virtual desktop;
- Game Porting Toolkit 3.0 (CrossOver-based 32on64) — same error plus a
  `virtual.c` assertion;
- two different game builds (a modded nitro_api build and clean WaRzOnE).

Root cause: the GoldSrc engine switches to its own allocated stack and raises
SEH exceptions from it. True 32-bit Wine (Linux multiarch) tolerates this,
but both macOS 32-on-64 approaches validate exception frames against the
thread's original stack limits and refuse to dispatch. Conclusion: **GoldSrc
does not run under Wine on modern macOS — use the native engine instead.**

## Setup (how ~/Games/cs16 was assembled)

1. Engine — Xash3D FWGS macOS arm64 build:
   <https://github.com/FWGS/xash3d-fwgs/releases> (`continuous` tag,
   `xash3d-fwgs-apple-arm64.tar.xz`), extracted into `~/Games/cs16`.
2. CS client — CS16Client macOS arm64:
   <https://github.com/Velaron/cs16-client/releases>
   (`CS16Client-macOS-arm64.zip`), unzipped over the same dir (provides
   `cstrike/cl_dlls/client_arm64.dylib`, `dlls/cs_arm64.dylib`, YaPB bots).
3. Game assets — `valve/` and `cstrike/` folders copied from the WaRzOnE
   install (itself unpacked with `innoextract`, see git history), *without*
   overwriting the arm64 dylibs (`cp -Rn`).

## Play

```sh
make counter-strike                    # or: games/counter-strike/run.sh
make counter-strike ARGS="-windowed"   # extra args pass through
```

Both go through `~/Games/cs16/play.sh`, which runs
`./xash3d -console -game cstrike` from the game folder (`-console` enables the
developer console). Add `-windowed` for windowed mode. For an offline match
against bots, see [Bots](#bots) below.

## The install is standalone

`~/Games/cs16` does not depend on this repo at runtime. Everything needed to
play lives in the folder:

```
~/Games/cs16/
  play.sh                     the launcher, resolves its own location
  README.txt                  player-facing notes
  cstrike/bots.cfg            bot settings, hand-editable
  Counter-Strike 1.6.app      double-click; a wrapper around play.sh
```

Install or refresh it with:

```sh
make counter-strike-standalone                      # + Counter-Strike 1.6.app
make counter-strike-standalone OFFLINE=1            # "(Bots).app" → straight into de_dust2
make counter-strike-standalone OFFLINE=1 MAP=cs_office
make counter-strike-standalone ARGS=--reset-bots    # restore this repo's bots.cfg
```

The repo is the **generator**, not a dependency: delete it and the game still
starts. `run.sh` here is a thin forwarder to the installed `play.sh`, so there
is one launch path instead of two that can drift.

### The folder is portable

Rename it, move it to another disk, or copy it to another Mac — `play.sh` uses
its own directory, and the app walks up from its bundle path to find the game
folder, so no absolute path is baked in. `Contents/Resources/game-dir` records
one anyway, used only if the app itself is dragged out of the game folder.

Two things matter when moving it to another Mac, both spelled out in the
installed `README.txt`: copy it as a **zip** (FAT/exFAT drops the executable
bits), and clear the quarantine flag afterwards —
`xattr -dr com.apple.quarantine <folder>` — because these binaries are not
signed by an identified developer.

### The app

A real `.app` bundle: Finder icon from `cstrike/game.ico`, no terminal window,
draggable to the Dock, findable in Spotlight. Both variants can coexist; they
use different bundle identifiers.

- Finder gives the process no terminal, so **everything the engine prints goes
  to `~/Library/Logs/counter-strike-16.log`**, overwritten on each launch. That
  is the first place to look when the app "does nothing".
- Env-var overrides such as `BOTS=12` have no place to be typed, so the app uses
  whatever `cstrike/bots.cfg` currently says.
- The icon is upscaled from a 32×32 `.ico`, so it looks soft at large sizes —
  that is the only art the game ships. `LSMinimumSystemVersion` is 14.0 (the
  engine's floor) rather than the CS16Client floor of 26.0, so the bundle does
  not block a locally rebuilt client; see [Requirements](#requirements).

### bots.cfg belongs to the install

`~/Games/cs16/cstrike/bots.cfg` is the source of truth for bot settings. Edit it
directly; nothing overwrites it — the installer only puts the repo's template
there when the file is absent, or when `--reset-bots` is passed. `BOTS=<n>`
rewrites its `bot_quota` line **persistently**, so the count sticks until it is
changed again.

Verified 2026-08-01: double-clicking the app starts the engine (`CS16Client
ver. 3911 initialized`) with no terminal window.

## Portable Windows build

The same three ingredients (Xash3D FWGS + CS16Client + these assets) also exist
as Windows x86 binaries, so a ready-to-run folder for a Windows PC can be built
from this Mac:

```sh
make counter-strike-windows ZIP=1     # ~/Games/cs16-windows{,.zip}
```

Copy it over, run `play.bat` — no installer, no Steam, no Wine. Confirmed
running well on Windows 2026-08-01. Details,
including why it must be 32-bit and why `liblist.gam` points at `dlls\mp.dll`
there instead of `dlls\cs.dll`: [`windows/README.md`](windows/README.md).

## Dedicated server

### Xash3D's own `-dedicated` mode

The engine has a real headless server mode and it works on this Mac:

```sh
make counter-strike-dedicated                                      # de_dust2, 12 slots, :27015
make counter-strike-dedicated MAP=cs_office PORT=27016 MAXPLAYERS=16
```

Verified 2026-07-31 — it loads the ReGameDLL game module and starts listening:

```
Dll loaded for game "Counter-Strike"
ReGameDLL version: 5.30.0.848-dev
Server IPv4 address 127.0.0.1:27015
12 player server started
```

No window, no client; it reads `server.cfg`, `maps/<map>_load.cfg` and
`game.cfg` like any GoldSrc dedicated server. The address it prints is only the
loopback one — `lsof` confirms the socket is `UDP *:27015`, i.e. reachable from
the LAN. Stop it with `Ctrl-C` (or `kill <pid>`).

What it does **not** give you:

- **No bots.** Every `bot_*` command comes back `Unknown command` —
  `UTIL_AreBotsAllowed` needs `bot_enable > 0` at game-DLL init, which cannot be
  set that early on a dedicated server. See [Bots only work on a listen
  server](#bots-only-work-on-a-listen-server). An empty dedicated server stays
  empty until humans join.
- **No Metamod / AMX Mod X** — both are Windows x86 DLLs, so no admin commands,
  stats or plugins.
- **Only Xash3D clients can connect.** Xash3D's GoldSrc protocol 48 support is
  one-way: this *client* can join Valve servers, but a stock CS 1.6 client
  cannot join this *server*.
- **A few cvars do not exist** in this engine and are simply skipped from
  `server.cfg`: `sv_pausable`, `sv_consistency`, `sv_voicecodec`,
  `sv_filetransfercompression`, `sv_lan_rate`, `mp_allowspectators`. The absence
  of `sv_consistency` in particular means no client-file consistency checking.

So it is fine for LAN games between Xash3D clients and for testing maps or
configs, and not usable as a public server.

### A real server: ReHLDS on Debian

To host a server that retail CS 1.6 clients can join, use the ReHLDS stack:
[`rehlds/README.md`](rehlds/README.md) — ReHLDS + ReGameDLL_CS + Metamod-R +
ReUnion + AMX Mod X + zBot, one-shot `install.sh`, a systemd unit, and a
`linux/amd64` Docker image (`make counter-strike-server`) for x86_64 hosts — that
image will not run on this Mac, Valve's engine crashes under QEMU emulation.
ReUnion is what lets this Xash3D client connect without a Steam ticket.

## Bots

The server DLL (`cstrike/dlls/cs_arm64.dylib`, a ReGameDLL build) ships the
**official CZ bots** — the same `bot_add` / `bot_quota` system as Condition
Zero. Nothing else is needed: no Metamod, no YaPB, and the install already has
`BotProfile.db` plus a `.nav` navigation mesh for all 27 maps.

### 8 bots join automatically — this is intentional

Any listen server gets **8 bots without asking**: the installer put `bots.cfg`
in `cstrike/` and made `listenserver.cfg` exec it, and `listenserver.cfg` runs
on every map start — including a plain `make counter-strike` (or a double-click)
followed by **Create Game** in the menu. `bot_quota 8` +
`bot_join_after_player 0` in `bots.cfg` is what pulls them in.

To play without bots, either run `bot_quota 0` / `bot_kick` in the console, or
set the quota to zero once:

```sh
BOTS=0 make counter-strike     # and every launch after it, until changed again
```

### Console commands (press `~` in game)

`bot_quota` is the master switch; `bot_add` / `bot_kick` adjust things on top of
it. Note that while the quota is set, the server refills kicked bots up to the
quota — lower `bot_quota` first if you want fewer of them for good.

| Command | What it does |
| --- | --- |
| `bot_quota 8` | keep 8 bots on the server (`0` = none) |
| `bot_add` | add one bot to the team that needs it |
| `bot_add_t` / `bot_add_ct` | add one bot to T / CT specifically |
| `bot_kick` | kick **all** bots (set `bot_quota 0` first, or they come back) |
| `bot_kick <name>` | kick one bot by name, e.g. `bot_kick [BOT]Wolf` |
| `bot_kill` | kill all bots (they respawn next round) |
| `bot_difficulty 2` | 0 easy, 1 normal, 2 hard, 3 expert — applies to bots added afterwards |
| `bot_join_team t` \| `ct` \| `any` | which team new bots join |
| `bot_freeze 1` / `bot_stop 1` | freeze bots in place (handy for aim practice) |
| `bot_knives_only`, `bot_pistols_only`, `bot_snipers_only`, `bot_all_weapons` | restrict bot weapons |
| `bot_chatter off` | silence bot radio/voice chatter |
| `bot_zombie 1` | bots stand still and do not shoot back |

Changes made in the console last until the map changes — `listenserver.cfg`
re-execs `bots.cfg` and restores the defaults. To make a change permanent, edit
`~/Games/cs16/cstrike/bots.cfg` (see below).

### Start a match against bots in one command

```sh
make counter-strike-offline                        # de_dust2 with 8 bots
make counter-strike-offline MAP=cs_office BOTS=12
```

### Persistent settings

`~/Games/cs16/cstrike/bots.cfg` is the source of truth — edit it directly.
Nothing overwrites it: `install-standalone.sh` only copies this repo's
`games/counter-strike/bots.cfg` template there when the file is absent, or when
`--reset-bots` is passed, and it appends the `exec bots.cfg` line to
`listenserver.cfg` once (original backed up as `listenserver.cfg.orig-no-bots`).

`BOTS=<n>` rewrites the `bot_quota` line in that file, so it is a **persistent**
change rather than a per-launch override.

### Bots only work on a listen server

Verified 2026-07-28: on `-dedicated` the game DLL never registers the bot
commands at all (`Unknown command "bot_quota"`), because `UTIL_AreBotsAllowed`
requires `bot_enable > 0` *at game-DLL init* on a dedicated server, and the
cvar cannot be set that early. On a listen server (`Create Server` in the menu,
or `+map <name>` on the command line) bots are always allowed — that is where
`make counter-strike-offline` runs them. This mirrors retail CS 1.6, where bots
were listen-server-only too.

### Bots path badly on some maps

On map load the console may print:

```
*** WARNING ***
The AI navigation data is from a different version of this map.
```

The WaRzOnE `.bsp` files do not all match the `.nav` files shipped alongside
them (seen on `de_dust2`). Bots still play, but they navigate poorly. To
regenerate the mesh for the current map, in the console:

```
bot_nav_analyze     // takes a few minutes, then saves maps/<map>.nav
```

### Why not YaPB

`cstrike/dlls/yapb_arm64.dylib` is present (it ships with CS16Client), but YaPB
expects to be loaded through Metamod — which has no arm64 build here — and it
needs its own `.graph` waypoint file per map, downloaded from the YaPB graph
database. The built-in CZ bots need none of that, so they are the route this
project uses.

## Troubleshooting

### "Create Server" is greyed out in the LAN menu

The WaRzOnE build's `cstrike/liblist.gam` points `gamedll` at
`addons\metamod\dlls\metamod.dll` — a Windows x86 DLL. The native arm64
engine can't load it, so the server-side game module fails to initialize and
hosting is disabled (fixed 2026-07-20). Verified via a dedicated-server test
(`./xash3d -dedicated -game cstrike -dev 3 +map de_dust2`) which loaded fully
and only failed on `bind: Address already in use` — i.e. the gamedll itself
loaded fine.

Fix: edit `~/Games/cs16/cstrike/liblist.gam`, change

```
gamedll "addons\metamod\dlls\metamod.dll"
```

to

```
gamedll "dlls\cs.dll"
```

(original backed up as `liblist.gam.orig-with-metamod`). This bypasses
Metamod and AMX Mod X — both are Windows x86 DLLs too and won't load on the
native arm64 engine, so admin/stats plugins from the WaRzOnE build are lost
along with them. A working Metamod/AMXX build compatible with Xash3D FWGS
would need to be sourced separately if those are needed later.

## Notes

- Native arm64: no Rosetta, no Wine — best possible performance and battery.
- Multiplayer: Xash3D FWGS speaks the GoldSrc protocol 48 well enough for
  most community servers, but some servers with strict anti-cheat may reject
  non-GoldSrc clients. LAN play with other Xash3D clients works fine.
- Updating: re-download the two archives (engine + client) and re-extract;
  assets don't change.
