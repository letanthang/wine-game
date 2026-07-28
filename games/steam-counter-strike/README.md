# Counter-Strike 1.6 (Steam)

> **Not the route this project uses for CS 1.6.** The game now runs on the
> native arm64 Xash3D FWGS engine — see `games/counter-strike/` and
> `docs/03-native-engines.md`. These notes are kept as the reference recipe for
> *future Steam titles*, which still need a Sikarugir wrapper.

- **Runs via:** Sikarugir wrapper with a WineCX engine (NOT a plain Wine prefix)
- **Distribution:** Steam (app id `10`)
- **Engine:** GoldSrc — old and light, runs well on Apple Silicon.
- **Fonts/locale:** none needed (no CJK text).

> **Why Sikarugir:** the plain-Wine route (Steam client in a wine-stable
> prefix) was tested on 2026-07-17 and **failed** — the modern CEF-based
> Steam client would not log in even with `-no-cef-sandbox -noverifyfiles`,
> and each Steam self-update breaks upstream Wine anew. Steam needs
> CrossOver-patched (CX) Wine engines, which wrapper tools ship.
> **Sikarugir** (successor of the discontinued Kegworks, renamed 2025-10,
> Apple Silicon-optimized with D3DMetal/DXMT backends) is the maintained
> free option. Paid fallback: CrossOver.

For the standalone non-Steam variant (installed directly with plain Wine into
its own prefix), see `games/counter-strike/`.

## Setup

### 1. Install Sikarugir

Requires macOS 14+ and Rosetta 2 (both satisfied on this host). Homebrew 6
needs the tap trusted first:

```sh
brew trust Sikarugir-App/sikarugir
brew install --cask Sikarugir-App/sikarugir/sikarugir
```

If Gatekeeper blocks the first launch: open once, then
**System Settings → Privacy & Security → Open Anyway**, or clear the
quarantine flag manually:

```sh
xattr -dr com.apple.quarantine /Applications/Sikarugir*.app
```

### 2. Create the wrapper

1. Open **Sikarugir** from `/Applications`.
2. Under **Engines**, click `+` and download the latest `WineCX`-based
   engine (the `CX` marks CrossOver-patched Wine — required for Steam).
3. Update the **Wrapper Version** if prompted.
4. Click **Create New Blank Wrapper**, name it `Counter-Strike`.
   It lands under `~/Applications/Sikarugir/Counter-Strike.app`.

### 3. Install Steam inside the wrapper

1. Download the official Windows Steam installer:
   <https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe>
2. Launch the wrapper — first run offers **Install Software** → **Choose
   Setup Executable** → pick `SteamSetup.exe`.
3. When the install finishes, select `steam.exe`
   (`C:\Program Files (x86)\Steam\steam.exe`) as the wrapper's Windows app.

### 4. Log in and install CS 1.6

Open the wrapper (double-click `Counter-Strike.app`), let Steam self-update,
log in, then install **Counter-Strike** (the 1.6 original) from the Library.

Optional: in the wrapper's **Advanced → Custom Commands**, add
`-applaunch 10` to Steam's arguments so the wrapper boots straight into CS.

### 5. Play

Double-click `~/Applications/Sikarugir/Counter-Strike.app`, or:

```sh
games/steam-counter-strike/run.sh
```

## Notes

- If the in-game mouse feels off, enable "Raw Input" in CS options, or use
  the wrapper's Wine Config (Sikarugir menu) → Graphics →
  "Automatically capture the mouse in full-screen windows".
- VAC: GoldSrc titles are generally fine under Wine, but as with any
  anti-cheat, official support is not guaranteed — play on community/official
  servers at your own discretion.
- Performance: expect smooth 60+ fps on the M4; GoldSrc predates
  Vulkan/DirectX 11 entirely (OpenGL), which Wine translates well.
- Future Steam games: create one Sikarugir wrapper each (Steam is bundled
  per-wrapper), or reuse this wrapper and add `-applaunch <appid>` variants.
- GoldSrc is OpenGL-based, so the default WineD3D backend is fine; the
  D3DMetal/DXMT backends matter for DirectX 11/12 games later.
