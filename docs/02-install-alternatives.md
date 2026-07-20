# Installing Wine without Homebrew

Alternatives to the deprecated `wine-stable` Homebrew cask, ordered by ease of use. Status as of 2026-07-06.

## 1. Gcenx GitHub builds (free — closest to the Homebrew route)

Gcenx packages the official Wine builds for macOS (the same binaries the Homebrew cask ships).

1. Go to <https://github.com/Gcenx/macOS_Wine_builds> → Releases.
2. Download the latest `Wine Stable` `.tar.xz`, extract, move `Wine Stable.app` to `/Applications`.
3. First launch is blocked by Gatekeeper → System Settings → Privacy & Security → **Open Anyway**.
4. The `wine` binary lives at `/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine` — add it to `PATH` if using the CLI.

Downside: manual updates.

## 2. Sikarugir (free — wraps each game into a standalone .app)

Maintained successor in the Wineskin lineage (Wineskin → Kegworks → Sikarugir, renamed 2025-10; Kegworks itself is discontinued): <https://github.com/Sikarugir-App/Sikarugir>. Builds a self-contained `.app` bundling Wine + prefix + the game, so launching the game is a normal double-click. Apple Silicon-optimized with selectable graphics backends (WineD3D, DXVK, D3DMetal, DXMT) and **WineCX engines** (CrossOver-patched Wine) — the only free way to run the Steam client, which fails under plain upstream Wine (confirmed 2026-07-17). Requires macOS 14+. **This project's chosen route for Steam games** — see `games/steam-counter-strike/README.md`.

## 3. CrossOver (paid, ~$74, 14-day trial)

Commercial Wine by CodeWeavers: <https://www.codeweavers.com/crossover>. Properly signed and notarized (no Gatekeeper friction), GUI bottle manager, commercial support, D3DMetal integration for demanding 3D games. Overkill for lightweight 2D games but the most polished option.

## 4. MacPorts (free — builds Wine from source locally)

```sh
sudo port install wine-stable
```

Locally compiled binaries are not quarantined, so Gatekeeper is not an issue. Downsides: the first build takes a long time, and it requires installing the MacPorts system alongside Homebrew.

## 5. Whisky (free, discontinued)

GPTK-based GUI, popular until development stopped in 2025. Still downloadable and functional, but unmaintained — not recommended for new setups.

## winetricks without Homebrew

`Wine Stable.app` does **not** bundle winetricks. It is a single POSIX shell script:

```sh
mkdir -p ~/bin
curl -L -o ~/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x ~/bin/winetricks
```

Add both winetricks and the Gcenx Wine binaries to `PATH` in `~/.zshrc`:

```sh
export PATH="$HOME/bin:/Applications/Wine Stable.app/Contents/Resources/wine/bin:$PATH"
```

**Caveat:** many winetricks verbs (`corefonts`, `cjkfonts`, ...) require `cabextract`, which macOS does not ship. Options:

1. Build cabextract from source (needs Xcode Command Line Tools only):

   ```sh
   curl -LO https://www.cabextract.org.uk/cabextract-1.11.tar.gz
   tar xzf cabextract-1.11.tar.gz && cd cabextract-1.11
   ./configure --prefix=$HOME && make && make install   # installs into ~/bin
   ```

2. Hybrid approach: `brew install winetricks` (pulls in cabextract as a dependency). These are plain formulae — not deprecated, no sudo needed; only the Wine *cask* has the Gatekeeper problem.

## Recommendation for this project

Split by distribution: **standalone (non-Steam) games** use the Gcenx CLI Wine with per-game prefixes (this repo's default workflow); **Steam games** use Sikarugir with a WineCX engine, because the Steam client only works under CrossOver-patched Wine.
