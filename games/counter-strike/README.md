# Counter-Strike 1.6 (standalone, non-Steam)

- **Prefix:** `~/wine-prefixes/counter-strike` (plain Wine, 64-bit)
- **Distribution:** your own standalone installer or game folder (no Steam)
- **Engine:** GoldSrc (OpenGL) — runs well under plain Wine on Apple Silicon.
- **Fonts/locale:** none needed.

This is the non-Steam variant. For the Steam edition (runs via a Sikarugir
wrapper because the Steam client does not work under plain Wine), see
`games/steam-counter-strike/`.

> **Warning:** non-Steam CS 1.6 builds circulating online are unofficial and
> frequently bundle malware/miners — and Wine exposes your whole disk to the
> game as drive `Z:`. Only use an installer you trust. Also mind licensing:
> the clean way to own CS 1.6 is the Steam release.

## Setup

### 1. Create the prefix

```sh
make prefix GAME=counter-strike
```

### 2. Install the game

Either run your installer inside the prefix:

```sh
WINEPREFIX=~/wine-prefixes/counter-strike wine /path/to/cs16-setup.exe
```

...or copy an existing game folder straight into the prefix, e.g. to
`~/wine-prefixes/counter-strike/drive_c/Games/Counter-Strike 1.6/`.

### 3. Play

```sh
games/counter-strike/run.sh
```

Adjust `GAME_EXE` at the top of `run.sh` to wherever `hl.exe` ended up.

## Troubleshooting

### Installer fails with `Cannot Import dll: ...ISSkinU.dll`

The installer is a *skinned* Inno Setup build; its skin DLL often fails to
load under Wine. Bypass the skinned UI by installing silently (hit 2026-07-20,
fixed this way):

```sh
WINEPREFIX=~/wine-prefixes/counter-strike wine /path/to/cs16-setup.exe \
  /VERYSILENT /NORESTART /DIR="C:\Games\Counter-Strike 1.6"
```

(`/SILENT` shows a progress bar instead; `/DIR` matches the `GAME_EXE` path
expected by `run.sh`.) If silent mode still fails, install the runtimes the
skin DLL needs and retry normally:

```sh
WINEPREFIX=~/wine-prefixes/counter-strike winetricks -q vcrun6 mfc42
```

### Installer crashes with `virtual_setup_exception stack overflow ... addr 0x0`

The 32-bit installer itself crashes under Wine 11's WoW64 (hit 2026-07-20,
even in silent mode). Don't run the installer at all — unpack it natively
with **innoextract** (`brew install innoextract`) and copy the payload in:

```sh
innoextract -s /path/to/CS16_Setup.exe -d /tmp/cs16   # game lands in /tmp/cs16/app
mv /tmp/cs16/app \
  ~/wine-prefixes/counter-strike/drive_c/Games/"Counter-Strike 1.6"
```

This is how the game was actually installed on this machine. Note: this build
ships `cstrike.exe` as its launcher (no classic `hl.exe`); `run.sh` points at
it.

### Game crashes at startup: `nested exception on signal stack` / `Exception frame is not in stack limits`

This modded build (nitro_api engine hooks) crashes a few seconds after launch
when driving the real display — `-windowed` does not help. Running it inside a
**Wine virtual desktop** fixes it (verified 2026-07-20):

```sh
wine explorer /desktop=cs16,1600x900 cstrike.exe
```

`run.sh` does this by default; change `DESKTOP_SIZE` there to resize.

### `Cannot Import dll: tier0.dll` for `cstrike_new.exe`

This build's `cstrike.exe` is a **self-updating launcher**: on start it
downloads updates (e.g. `cstrike_new.exe`) into the *current working
directory* and runs them from there. If you launch the game from any other
directory, the updated exe lands away from the game's DLLs and fails to load.
`run.sh` handles this by `cd`-ing into the game dir first (fixed 2026-07-20).
The launcher also phones an update server on every start; expect harmless
`winsock`/`secur32` fixme spam in the log.

## Notes

- Multiplayer: non-Steam clients cannot join Steam-authenticated/VAC servers;
  they work on community servers running Reunion/dproto and on LAN
  (`sv_lan 1`). Make sure the build speaks **protocol 48** or servers will
  reject it as outdated.
- If the mouse feels off, enable "Raw Input" in CS options, or
  `WINEPREFIX=~/wine-prefixes/counter-strike winecfg` → Graphics →
  "Automatically capture the mouse in full-screen windows".
- Performance: GoldSrc is OpenGL; expect smooth 60+ fps on the M4.
