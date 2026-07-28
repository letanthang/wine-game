# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language convention

- Converse with the user in **Vietnamese**.
- Write all documentation, code comments, scripts, and commit messages in **English**.

## What this project is

This is not a software project. It documents installing and configuring **Wine on macOS (Apple Silicon)** to run Windows games, and keeps per-game setup notes and helper scripts. The first target game is **A Piece of Blue Glass Moon** (the Tsukihime remake).

## Host environment

- Apple Silicon (arm64), macOS 26.x — Wine runs x86_64 code through Rosetta 2 (already installed).
- Homebrew is the package manager.
- Wine install uses the **hybrid approach** (see README.md and docs/01-install-wine.md): `Wine Stable.app` from the Gcenx GitHub builds extracted into `/Applications` (the `wine-stable` Homebrew cask is deprecated, disabled 2026-09-01), plus `brew install winetricks` for winetricks/cabextract.
- Wine CLI binaries live at `/Applications/Wine Stable.app/Contents/Resources/wine/bin/` and are added to `PATH` in `~/.zshrc`.
- Other fallbacks: CrossOver (paid), Sikarugir (free Wineskin/Kegworks successor) — see docs/02-install-alternatives.md.
- Some games skip Wine entirely and run on a **native arm64 engine re-implementation** — see docs/03-native-engines.md.

## Conventions

- **Native engine first.** If a game has a maintained native arm64 engine re-implementation, use it instead of Wine. Decided for **Counter-Strike 1.6 → Xash3D FWGS + CS16Client**, installed at `~/Games/cs16`, launched by `games/counter-strike/run.sh` (`make counter-strike`): GoldSrc crashes under every Wine variant on this machine with `err:seh:NtRaiseException Exception frame is not in stack limits` (tested exhaustively 2026-07-20, not fixable from the Wine side). Details in docs/03-native-engines.md and games/counter-strike/README.md.
- **Steam games** run via **Sikarugir wrappers with a WineCX engine** (e.g. `games/steam-counter-strike/`; Sikarugir is the maintained successor of Kegworks, which is discontinued) — the modern Steam client does not work under plain upstream Wine (confirmed by testing 2026-07-17); only CrossOver-patched engines run it. Each game still gets `games/<game-slug>/` docs and a `run.sh` that opens its wrapper. CS 1.6 was originally planned for this route; it now uses the native Xash3D build instead, and `games/steam-counter-strike/` is kept as reference for future Steam titles.
- **Non-Steam games** get their own plain-Wine prefix under `~/wine-prefixes/<game-slug>` (e.g. `~/wine-prefixes/blue-glass-moon`). Never install games into the default `~/.wine` prefix.
- All prefixes use `WINEARCH=win64` unless a game specifically needs 32-bit.
- Per-game docs live in `games/<game-slug>/README.md`; launcher scripts in `games/<game-slug>/run.sh`.
- General setup and troubleshooting docs live in `docs/`.
- Visual novels with Japanese text may need CJK fonts (`winetricks cjkfonts`) and a Japanese locale (`LC_ALL=ja_JP.UTF-8`) — record what each game actually needed in its README.

## Common commands

```sh
# Launch Counter-Strike 1.6 (native Xash3D, no Wine)
make counter-strike
make counter-strike ARGS="-windowed"    # or ARGS="-dedicated" for a headless server

# Create a new 64-bit prefix for a game
WINEPREFIX=~/wine-prefixes/<game-slug> WINEARCH=win64 wineboot

# Open Wine configuration for a prefix
WINEPREFIX=~/wine-prefixes/<game-slug> winecfg

# Run an installer or game exe inside a prefix
WINEPREFIX=~/wine-prefixes/<game-slug> wine /path/to/setup.exe

# Install common dependencies into a prefix
WINEPREFIX=~/wine-prefixes/<game-slug> winetricks corefonts cjkfonts
```
