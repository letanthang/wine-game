# Counter-Strike 1.6 (standalone, native via Xash3D)

- **Runs via:** Xash3D FWGS engine, **native Apple Silicon arm64 — no Wine**
- **Install location:** `~/Games/cs16`
- **Client/bots:** CS16Client (arm64) + bundled YaPB bots for offline play
- **Assets:** extracted from the user's CS 1.6 WaRzOnE installer
- **Fonts/locale:** none needed.

For the Steam edition (Sikarugir wrapper), see `games/steam-counter-strike/`.

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
games/counter-strike/run.sh            # extra args pass through
```

Runs `./xash3d -game cstrike` from `~/Games/cs16`. Add `-windowed` for
windowed mode. Offline bots: create a server and YaPB adds bots (see YaPB
docs for commands, default `yb add`).

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
