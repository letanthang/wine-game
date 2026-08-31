# Counter-Strike 1.6 — macOS arm64 build

`build.sh` assembles `~/Games/cs16-mac` from scratch: the native Xash3D FWGS
engine and CS16Client are downloaded, the game assets come from a local install,
and `install-standalone.sh` finishes the folder off with `play.sh`, `bots.cfg`
and the double-clickable `Counter-Strike 1.6.app`. No Wine, no Steam — see the
[game README](../README.md) for why GoldSrc itself cannot run here.

```sh
make counter-strike-mac                  # build + standalone install
make counter-strike-mac ARGS=--force     # overwrite an existing ~/Games/cs16-mac
make counter-strike-mac ARGS=--slim      # skip the 430 MB valve/ assets
make counter-strike-mac ARGS=--refresh   # re-download the engine and client
```

## The three parts

| Part | Where it comes from |
| --- | --- |
| Engine | `xash3d-fwgs-apple-arm64.tar.xz`, [FWGS/xash3d-fwgs](https://github.com/FWGS/xash3d-fwgs/releases) `continuous` tag |
| Client | `CS16Client-macOS-arm64.zip`, [Velaron/cs16-client](https://github.com/Velaron/cs16-client/releases) `continuous` tag |
| Assets | `cstrike/` and `valve/` from `SRC` (default `~/Games/assets`) |

Both archives are cached in `~/Games/.cache/cs16-mac`; `--refresh` re-downloads
them. They unpack flat into the game folder — the engine tarball has a `./`
root, the client zip a `cstrike/` one.

## The asset source

`~/Games/assets` is a plain CS 1.6 install kept only as a source of content
(originally the WaRzOnE install unpacked with `innoextract`, see the git
history). Only its `cstrike/` and `valve/` folders are read, and `rsync
--ignore-existing` means every file the engine or CS16Client already placed
wins — a stale `client_arm64.dylib` in the source can never overwrite the
freshly downloaded one.

Left behind on purpose: `*.dll` / `*.exe` (nothing on arm64 macOS loads them),
`addons/` (Metamod / AMX Mod X, which do not load on Xash3D), `bin/` (Valve
TrackerUI), `bots.cfg` (installed from the repo template instead) and local
state such as `config.cfg`, `video.cfg` and `SAVE/`.

Point `SRC=<dir>` at any other CS 1.6 install to use it instead.

## After the build

`cstrike/liblist.gam` is rewritten to `gamedll "dlls\cs.dll"` — the engine
appends the platform suffix itself and loads `dlls/cs_arm64.dylib`. Pointing it
anywhere else (the WaRzOnE `metamod.dll`, say) makes the server side fail to
initialise and greys out "Create Server".

The quarantine flag is cleared from the whole folder by
`../remove-quarantine.sh` (`xattr -dr com.apple.quarantine`): these binaries are
not signed by an identified developer, and Gatekeeper kills them with no useful
message otherwise. The same script is installed into the game folder as
`remove-quarantine.sh`, because a folder that is zipped up and copied to another
Mac arrives quarantined again:

```sh
cd ~/Games/cs16-mac
./remove-quarantine.sh          # or: zsh remove-quarantine.sh
```

`--no-standalone` stops after assembling, leaving the launcher and the `.app`
out.

## Verifying a build

The engine can be started headless, which exercises the game module and the
assets without opening a window:

```sh
cd ~/Games/cs16-mac
./xash3d -dedicated -console -game cstrike -port 27099 +maxplayers 4 +map de_dust2
```

`Dll loaded for game "Counter-Strike"`, a `ReGameDLL version:` line and
`4 player server started` mean the build is sound.
