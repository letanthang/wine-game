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

Runs `./xash3d -console -game cstrike` from `~/Games/cs16` (`-console` enables
the developer console). Add `-windowed` for windowed mode. For an offline match
against bots, see [Bots](#bots) below.

## Bots

The server DLL (`cstrike/dlls/cs_arm64.dylib`, a ReGameDLL build) ships the
**official CZ bots** — the same `bot_add` / `bot_quota` system as Condition
Zero. Nothing else is needed: no Metamod, no YaPB, and the install already has
`BotProfile.db` plus a `.nav` navigation mesh for all 27 maps.

### 8 bots join automatically — this is intentional

Any listen server started from this repo's launcher gets **8 bots without
asking**: `run.sh` installs `bots.cfg` and makes `listenserver.cfg` exec it, and
`listenserver.cfg` runs on every map start — including a plain
`make counter-strike` followed by **Create Game** in the menu. `bot_quota 8` +
`bot_join_after_player 0` in `bots.cfg` is what pulls them in.

To play without bots, either run `bot_quota 0` / `bot_kick` in the console, or
launch with `BOTS=0`:

```sh
BOTS=0 games/counter-strike/run.sh     # no bots this session
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
`games/counter-strike/bots.cfg` in this repo (see below).

### Start a match against bots in one command

```sh
make counter-strike-offline                        # de_dust2 with 8 bots
make counter-strike-offline MAP=cs_office BOTS=12
```

### Persistent settings

`games/counter-strike/bots.cfg` in this repo is the source of truth. `run.sh`
copies it into `~/Games/cs16/cstrike/` on every launch and appends an
`exec bots.cfg` line to `listenserver.cfg` / `server.cfg` once (originals
backed up as `*.orig-no-bots`). Edit the repo copy to change defaults; use
`BOTS=<n>` to override the bot count for a single launch — `run.sh` rewrites
the `bot_quota` line in the installed copy.

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
