# Counter-Strike 1.6 on Xash3D — portable Windows build

`build.sh` assembles a **self-contained Windows folder** for CS 1.6 on the
Xash3D FWGS engine: copy it to a Windows PC, run `play.bat`, done. No
installer, no Steam, no Wine, no registry entries.

The script runs on this Mac and takes the game assets from the local
`~/Games/cs16` install (the native arm64 build documented in
[`../README.md`](../README.md)), pairing them with the **Windows** engine and
client binaries downloaded from upstream.

## Build it

```sh
make counter-strike-windows                 # ~/Games/cs16-windows  (822 MB)
make counter-strike-windows ZIP=1           # plus ~/Games/cs16-windows.zip
make counter-strike-windows SLIM=1 ZIP=1    # ~400 MB, cstrike only
```

or call the script directly for the full set of options:

```sh
games/counter-strike/windows/build.sh --help
```

| Flag | Effect |
| --- | --- |
| `--slim` | skip the Half-Life `valve/` assets (~430 MB); the engine's own `valve/extras.pk3` is kept |
| `--zip` | also produce `<out>.zip` next to the output folder |
| `--refresh` | re-download the engine/client archives instead of reusing the cache |
| `--force` | overwrite an existing output folder |

`SRC=`, `OUT=` and `CACHE=` override the source install, the output folder and
the download cache (`~/Games/cs16`, `~/Games/cs16-windows`,
`~/Games/.cache/cs16-windows`).

## Everything is 32-bit x86 — this is forced

CS16Client publishes exactly one Windows artifact, `CS16Client-Windows-X86.zip`
(i386). There is no 64-bit Windows client, so the engine half must be the
matching `xash3d-fwgs-win32-i386.7z`, not `-amd64`. All binaries in the package
are `PE32 … Intel 80386`. This is not a limitation in practice — 32-bit
binaries run fine on 64-bit Windows.

## What the script actually does

1. Downloads and extracts the engine, `xash3d-fwgs-win32-i386.7z` from the
   FWGS **rolling `continuous` tag**.
2. Extracts `CS16Client-Windows-X86.zip` over it — this provides
   `cstrike/cl_dlls/client.dll`, `cstrike/cl_dlls/menu.dll`,
   `cstrike/dlls/mp.dll` (ReGameDLL with the CZ bots) and `yapb.dll`.
3. Deletes the `*.pdb` / `*.lib` files from both archives — ~180 MB of debug
   symbols a player has no use for.
4. `rsync --ignore-existing` copies `cstrike/` (and `valve/` unless `--slim`)
   from the source install. `--ignore-existing` is the load-bearing flag: it
   makes every file the engine or CS16Client already placed win, so the
   WaRzOnE `client.dll` / `mp.dll` never overwrite the CS16Client ones. This is
   the `cp -Rn` rule from the macOS setup.
5. Rewrites `cstrike/liblist.gam` to `gamedll "dlls\mp.dll"` (see below).
6. Installs this repo's `bots.cfg` and makes `listenserver.cfg` exec it.
7. Writes `play.bat`, `play-offline.bat`, `dedicated-server.bat`, a player-facing
   `README.txt`, and a `BUILD_INFO.txt` recording the SHA-256 of both archives.

Deliberately **excluded** from the asset copy: `*.dylib` and `SDL2.framework`
(macOS binaries), `addons/` (Metamod / AMX Mod X / dproto — none of them load
on Xash3D), `bin/` (Valve TrackerUI), `cl_dlls/GameUI.dll` (CS16Client ships its
own menu), and the machine-specific `config.cfg` / `video.cfg` / `opengl.cfg`
plus local state (`cache/`, `logs/`, `SAVE/`, `*.bak`, `*.orig-*`).

## The gamedll name differs from macOS

| Platform | `liblist.gam` gamedll | Actual file |
| --- | --- | --- |
| macOS arm64 | `dlls\cs.dll` | `cstrike/dlls/cs_arm64.dylib` |
| Windows x86 | `dlls\mp.dll` | `cstrike/dlls/mp.dll` |

Xash3D maps the name in `liblist.gam` onto a platform-specific file. On
non-Windows targets CS16Client names its module `cs_<arch>`; on Windows it keeps
the original Valve name `mp.dll`. Copying the macOS value over would leave the
server side uninitialised and grey out **Create Server** — the same symptom the
WaRzOnE `metamod.dll` value causes (see the Troubleshooting section of
[`../README.md`](../README.md)).

`liblist.gam` has CRLF line endings, so the rewrite in `build.sh` matches up to
the closing quote rather than to end-of-line, leaving the `\r` intact.

## Requirements on the Windows machine

- Windows 7 or newer, 32- or 64-bit.
- **Microsoft Visual C++ Redistributable (x86)** —
  <https://aka.ms/vs/17/release/vc_redist.x86.exe>. Confirmed necessary:
  `cstrike/cl_dlls/client.dll` and `cstrike/dlls/mp.dll` import `MSVCP140.dll`
  and `VCRUNTIME140.dll`. Without it the game fails at startup with a
  missing-DLL error.
- Do not unpack into `C:\Program Files` — the engine writes configs and
  screenshots next to the executable. `C:\Games\cs16` is a good spot.

## Limits carried over from the macOS build

These are properties of Xash3D + CS16Client, not of this packaging:

- **No Metamod / AMX Mod X**, so no admin, stats or plugins.
- **Bots are listen-server only.** `play.bat` / `play-offline.bat` get the 8 CZ
  bots from `bots.cfg`; `dedicated-server.bat` gets none, because the game
  module refuses to register the `bot_*` commands on a dedicated server.
- **Joining public servers** usually works (GoldSrc protocol 48), but servers
  with strict anti-cheat may reject a non-GoldSrc client.
- Bots path badly on maps whose `.bsp` and `.nav` versions disagree — run
  `bot_nav_analyze` in the console to regenerate the current map's mesh.

## Verification status

**Confirmed running well on Windows, 2026-08-01** — first package built by this
script (engine `6958db11…`, client `29d89b3d…`, see `BUILD_INFO.txt`), full
variant with the `valve/` assets. So the recipe below is known-good end to end,
not just structurally sound.

Checks done on the macOS side while assembling: all binaries are PE32 i386, no
macOS or debug leftovers remain, `liblist.gam` points at `dlls\mp.dll`, the 27
`.nav` meshes are present, and `listenserver.cfg` execs `bots.cfg`.

Still untested from here, so treat as open until someone tries them:

- `--slim` packages (no `valve/`) — nothing has run without the Half-Life
  assets yet.
- `dedicated-server.bat`.
- Whether the VC++ x86 redistributable actually had to be installed, or was
  already present on that machine.

## Updating

Both upstream halves come from rolling `continuous` tags, so the same URLs serve
new binaries over time. Re-run with `--refresh --force` to pick them up; the
assets are unchanged. `BUILD_INFO.txt` inside a package identifies exactly which
build it was made from.
