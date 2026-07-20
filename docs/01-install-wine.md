# Installing Wine on macOS (Apple Silicon) — hybrid approach

Status as of 2026-07-17. Host: Apple Silicon (arm64), macOS 26.x, Rosetta 2 installed.

This project uses the **hybrid approach**:

- **Wine** comes from the Gcenx GitHub builds (`Wine Stable.app`) — avoids the deprecated `wine-stable` Homebrew cask.
- **winetricks + cabextract** come from Homebrew — these are plain formulae (not deprecated, no sudo needed); only the Wine *cask* has the Gatekeeper problem.

See `docs/02-install-alternatives.md` for other options (Sikarugir, CrossOver, MacPorts).

## 1. Prerequisites

Rosetta 2 lets the Intel build of Wine run on Apple Silicon. Verify it is present:

```sh
arch -x86_64 /usr/bin/true && echo "Rosetta OK"
```

If missing, install it with:

```sh
softwareupdate --install-rosetta --agree-to-license
```

## 2. Install Wine (Gcenx build)

Download the latest **stable** build from <https://github.com/Gcenx/macOS_Wine_builds/releases> (asset named `wine-stable-<version>-osx64.tar.xz`), or via CLI:

```sh
curl -L -o /tmp/wine-stable.tar.xz \
  https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz
tar -xJf /tmp/wine-stable.tar.xz -C /Applications
```

This puts `Wine Stable.app` into `/Applications`. The `wine` CLI binaries live at:

```
/Applications/Wine Stable.app/Contents/Resources/wine/bin/
```

Note: files downloaded with `curl` are not quarantined, so Gatekeeper usually
does not block them. If macOS still complains on first run ("developer cannot
be verified"), go to **System Settings → Privacy & Security → Open Anyway**.

## 3. Install winetricks + cabextract (Homebrew)

```sh
brew install winetricks   # pulls in cabextract, needed by corefonts/cjkfonts verbs
```

## 4. Environment variables

Add the Wine binaries to `PATH` in `~/.zshrc`:

```sh
export PATH="/Applications/Wine Stable.app/Contents/Resources/wine/bin:$PATH"
```

Then reload the shell (`source ~/.zshrc`) and verify:

```sh
wine --version        # expect: wine-11.0
winetricks --version
```

## 5. Prefix layout used in this project

One prefix per game under `~/wine-prefixes/`:

```sh
WINEPREFIX=~/wine-prefixes/<game-slug> WINEARCH=win64 wineboot
```

A prefix is a self-contained fake `C:\` drive. Keeping one per game means a
broken or heavily-tweaked game never affects the others, and deleting a game
is just deleting its prefix directory.

## Updating Wine later

The Gcenx build does not auto-update. To upgrade: download the newer
`wine-stable-*.tar.xz` release, delete the old `/Applications/Wine Stable.app`,
and extract the new one in its place. Prefixes are stored separately under
`~/wine-prefixes/` and survive the swap.
