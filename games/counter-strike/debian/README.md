# Counter-Strike 1.6 on Xash3D — portable Debian build

`build.sh` assembles a **self-contained Linux folder** for CS 1.6 on the Xash3D
FWGS engine: copy it to a Debian machine, run `./play.sh`, done. No installer,
no Steam, no Wine.

The script runs on this Mac and takes the game assets from the local
`~/Games/assets` install (the same source the [macOS](../mac/README.md) and
[Windows](../windows/README.md) builds use), pairing them with the **Linux**
engine and client binaries downloaded from upstream. Nothing is compiled.

This is the game **client**. The dedicated server for Debian is a different
stack, ReHLDS — see [`../rehlds/README.md`](../rehlds/README.md).

## Build it

```sh
make counter-strike-debian                 # ~/Games/cs16-debian  (877 MB)
make counter-strike-debian TAR=1           # plus ~/Games/cs16-debian.tar.gz (416 MB)
make counter-strike-debian ARCH=i386       # 32-bit package
make counter-strike-debian SLIM=1 TAR=1    # cstrike only, no valve/ assets
```

or call the script directly for the full set of options:

```sh
games/counter-strike/debian/build.sh --help
```

| Flag | Effect |
| --- | --- |
| `--arch <arch>` | `amd64` (default) or `i386` |
| `--slim` | skip the Half-Life `valve/` assets (~430 MB); the engine's own `valve/extras.pk3` is kept |
| `--tar` | also produce `<out>.tar.gz` next to the output folder |
| `--refresh` | re-download the engine/client archives instead of reusing the cache |
| `--force` | overwrite an existing output folder |

`SRC=`, `OUT=` and `CACHE=` override the source install, the output folder and
the download cache (`~/Games/assets`, `~/Games/cs16-debian`,
`~/Games/.cache/cs16-debian`).

## Architectures

The build machine cannot know what the target is, so the architecture is a flag.

| `--arch` | Engine archive | CS16Client archive | Game module |
| --- | --- | --- | --- |
| `amd64` | `xash3d-fwgs-linux-amd64.tar.gz` | `CS16Client-Linux-x86_64.tar.gz` | `cstrike/dlls/cs_amd64.so` |
| `i386` | `xash3d-fwgs-linux-i386.tar.gz` | `CS16Client-Linux-i386.tar.gz` | `cstrike/dlls/cs.so` |

**arm64 is not available.** FWGS publishes a `linux-arm64` engine, but
CS16Client has no Linux arm64 build, and the engine and the client libraries
must match. `--arch arm64` is refused with that explanation rather than
producing a folder that cannot load its game module.

## Copy it as a tarball, not a zip

The engine folder contains symlinks (`libSDL2-2.0.so.0` →
`libSDL2-2.0.so.0.3200.10`, the ffmpeg libraries) and relies on executable
bits. A zip file or a FAT/exFAT USB stick loses both. Use `--tar` and unpack on
the target:

```sh
tar -xzf cs16-debian.tar.gz
cd cs16-debian
./play.sh
```

`rsync -a` and `scp -r` of the tarball work as well. The tarball is written with
`COPYFILE_DISABLE=1` so macOS tar adds no `._*` AppleDouble entries.

## Requirements on the Debian machine

- x86 Debian or a derivative, with a desktop session and working OpenGL.
- **`libfreetype6`** — the one library the package links against that it does
  not bring along (`cstrike/cl_dlls/menu*.so` needs `libfreetype.so.6`).
- **`libgl1`** — the renderer is opened at run time.
- `libstdc++6`, `libgcc-s1`, `libc6` — present on any Debian install.

SDL2 and ffmpeg are **not** needed from the system: the engine archive ships its
own copies and the binaries find them through a `$ORIGIN` run-path.

```sh
sudo apt install libfreetype6 libgl1
```

For the i386 package on an amd64 system:

```sh
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install libc6:i386 libstdc++6:i386 libfreetype6:i386 libgl1:i386
```

### play.sh checks this, and never installs anything

`build.sh` runs on macOS and has no business with `apt`. The check lives in
`play.sh`, which runs on the target: before starting the engine it resolves the
libraries of `xash3d`, `libxash.so` and the CS16Client modules with `ldd`, looks
for `libGL.so.1`, and if anything is missing prints the exact `apt install`
line and exits. It does not call `sudo` or `apt` itself.

The check matters because the failure it catches is silent: without
`libfreetype.so.6` the menu library does not load, the game reports
`native object "MenuFactory" is unavailable` and falls back to the engine's own
menu — the same symptom the macOS build had before its libraries were vendored.

`SKIP_LIB_CHECK=1 ./play.sh` starts the game regardless.

## What the script actually does

1. Downloads the engine and client archives for the chosen architecture from
   the two **rolling `continuous` tags**.
2. Extracts the engine with `--strip-components 1` (its tarball wraps everything
   in an `xash3d-fwgs-linux-<arch>/` folder), then the client over it.
3. Deletes the AppImage scaffolding (`AppRun`, `.DirIcon`,
   `xash3d-fwgs.desktop`) — `AppRun` only works with `$APPDIR` set.
4. `rsync --ignore-existing` copies `cstrike/` (and `valve/` unless `--slim`)
   from the source install, so every file the engine or CS16Client already
   placed wins.
5. Rewrites `cstrike/liblist.gam` to `gamedll "dlls\cs.dll"`, and a
   `gamedll_linux` line too if the source install has one.
6. Installs this repo's `bots.cfg` and makes `listenserver.cfg` exec it.
7. Installs `play.sh`, a player-facing `README.txt`, and a `BUILD_INFO.txt`
   recording the SHA-256 of both archives.

Deliberately **excluded** from the asset copy: `*.dll` / `*.exe`, `*.dylib` and
`*.so` (only the downloaded Linux libraries belong in the package), `addons/`
(Metamod / AMX Mod X / dproto — none of them load on Xash3D), `bin/` (Valve
TrackerUI), and the machine-specific `config.cfg` / `video.cfg` / `opengl.cfg`
plus local state (`cache/`, `logs/`, `SAVE/`, `*.bak`, `*.orig-*`).

## The gamedll name

`liblist.gam` keeps the same value as the macOS build, `dlls\cs.dll`. The engine
derives the Linux name from it — `.dll` becomes `.so` and the architecture
suffix is added on 64-bit — and loads `dlls/cs_amd64.so` or `dlls/cs.so`.
Windows is the odd one out with `dlls\mp.dll`; see
[`../windows/README.md`](../windows/README.md).

## Limits carried over from the other builds

These are properties of Xash3D + CS16Client, not of this packaging:

- **No Metamod / AMX Mod X**, so no admin, stats or plugins.
- **Bots are listen-server only.** `./play.sh -dedicated` gets none, because the
  game module refuses to register the `bot_*` commands on a dedicated server.
- **Joining public servers** usually works (GoldSrc protocol 48), but servers
  with strict anti-cheat may reject a non-GoldSrc client.

## Verification status

**Not yet run on a Debian machine.** Checked on the macOS side only, 2026-10-13
(engine `3a4c032d…`, client `7959a59e…`):

- both `amd64` and `i386` packages assemble; the binaries are ELF x86-64 and
  ELF 32-bit i386 respectively;
- no macOS or Windows binaries remain, and the only `.so` files under `cstrike/`
  are the four CS16Client ones;
- `liblist.gam` points at `dlls\cs.dll`, the 27 `.nav` meshes are present, and
  `listenserver.cfg` execs `bots.cfg`;
- the tarball keeps the symlinks and executable bits and has no `._*` entries;
- the library requirements above were read from the ELF headers
  (`objdump -p`), not observed with `ldd` on a real system.

Still open until someone tries them on Debian:

- the game actually starting, rendering and showing the CS16Client menu;
- `play.sh`'s library check — written against `ldd`'s documented output, never
  executed (Docker was not running on the build machine);
- the `i386` package, `--slim` packages, and `./play.sh -dedicated`.

## Updating

Both upstream halves come from rolling `continuous` tags, so the same URLs serve
new binaries over time. Re-run with `--refresh --force` to pick them up; the
assets are unchanged. `BUILD_INFO.txt` inside a package identifies exactly which
build it was made from.
