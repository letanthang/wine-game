# wine-game

Notes and helper scripts for running Windows games on macOS (Apple Silicon)
with Wine. First target game: **A Piece of Blue Glass Moon** (the Tsukihime remake).

- Setup guide: [docs/01-install-wine.md](docs/01-install-wine.md)
- Install alternatives: [docs/02-install-alternatives.md](docs/02-install-alternatives.md)
- Native engines (no Wine): [docs/03-native-engines.md](docs/03-native-engines.md)
- CS 1.6 dedicated server on Debian: [games/counter-strike/rehlds/README.md](games/counter-strike/rehlds/README.md)
- Per-game notes: `games/<game-slug>/README.md`, launchers in `games/<game-slug>/run.sh`

## Games and how each one runs

Not every game goes through Wine — if a maintained native arm64 engine exists,
it wins. Check that first.

| Game | Route | Notes |
| --- | --- | --- |
| [Counter-Strike 1.6](games/counter-strike/README.md) | **Native Xash3D FWGS** (no Wine) | `make counter-strike`, or `make counter-strike-offline MAP=de_dust2 BOTS=8` for a match against bots. GoldSrc crashes under every Wine variant on macOS — see [docs/03-native-engines.md](docs/03-native-engines.md) |
| [CS 1.6 dedicated server](games/counter-strike/rehlds/README.md) | **ReHLDS on Debian** (x86_64, no Wine) | ReHLDS + ReGameDLL + Metamod-R + ReUnion + AMXX + bots, one-shot `install.sh`. `make counter-strike-server` runs it in Docker, but only on x86_64 hosts — the engine will not run under emulation on Apple Silicon |
| A Piece of Blue Glass Moon | Plain Wine prefix | `make prefix GAME=blue-glass-moon FONTS=1` |
| [Steam games](games/steam-counter-strike/README.md) | Sikarugir wrapper (WineCX engine) | Steam client does not work under plain upstream Wine |

## Installation

Hybrid approach: Wine from the [Gcenx GitHub builds](https://github.com/Gcenx/macOS_Wine_builds),
winetricks + cabextract from Homebrew. Requires an Apple Silicon Mac with
Rosetta 2 and Homebrew already installed.

### One-shot install

```sh
make install        # runs scripts/install.sh; safe to re-run
```

This performs steps 1–4 below (Rosetta check, Wine download, winetricks,
PATH in `~/.zshrc`). The manual steps follow if you prefer to run them yourself.

### 1. Verify Rosetta 2

```sh
arch -x86_64 /usr/bin/true && echo "Rosetta OK"
# If missing:
# softwareupdate --install-rosetta --agree-to-license
```

### 2. Install Wine (Gcenx stable build)

```sh
curl -L -o /tmp/wine-stable.tar.xz \
  https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz
tar -xJf /tmp/wine-stable.tar.xz -C /Applications
rm /tmp/wine-stable.tar.xz
```

If macOS blocks the first run: **System Settings → Privacy & Security → Open Anyway**.

### 3. Install winetricks (Homebrew)

```sh
brew install winetricks   # also installs cabextract
```

### 4. Environment variables

Append to `~/.zshrc`:

```sh
# Wine (Gcenx build) CLI tools
export PATH="/Applications/Wine Stable.app/Contents/Resources/wine/bin:$PATH"
```

Reload and verify:

```sh
source ~/.zshrc
wine --version        # expect: wine-11.0
winetricks --version
```

### 5. Create a prefix for a game

**Games with a native engine do not use these prefixes** — e.g. Counter-Strike
1.6 runs on native arm64 Xash3D FWGS, no Wine at all; see
[games/counter-strike/README.md](games/counter-strike/README.md) and
[docs/03-native-engines.md](docs/03-native-engines.md).

**Steam games do not use these prefixes either** — the modern Steam client does
not work under plain upstream Wine (tested 2026-07-17). Steam games run via
Sikarugir wrappers instead; see
[games/steam-counter-strike/README.md](games/steam-counter-strike/README.md).

**Non-Steam games** get one 64-bit prefix each under `~/wine-prefixes/`:

```sh
make prefix GAME=blue-glass-moon FONTS=1   # standalone game + corefonts/cjkfonts for Japanese text
```

Or manually:

```sh
export WINEPREFIX=~/wine-prefixes/blue-glass-moon
WINEARCH=win64 wineboot

# Common dependencies for visual novels (fonts incl. Japanese):
winetricks corefonts cjkfonts

# Run the game installer / exe inside the prefix:
wine /path/to/setup.exe
```

Games with Japanese text may additionally need a Japanese locale when launching:

```sh
LC_ALL=ja_JP.UTF-8 wine /path/to/game.exe
```
