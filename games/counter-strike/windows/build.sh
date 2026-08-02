#!/bin/zsh
# Assemble a ready-to-run Windows build of Counter-Strike 1.6 on Xash3D FWGS.
#
# Runs on this Mac and produces a self-contained folder (optionally a .zip) that
# is copied to a Windows PC and started with play.bat — no installer, no Steam,
# no Wine. See README.md in this directory for the details.
#
# The package is three parts glued together:
#   1. Xash3D FWGS engine  — win32-i386 build from the rolling `continuous` tag
#   2. CS16Client          — Windows X86 build (client.dll / menu.dll / mp.dll)
#   3. Game assets         — copied from the local ~/Games/cs16 install
#
# Everything is 32-bit x86: CS16Client publishes no 64-bit Windows binaries, so
# the engine must match it.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_GAME_DIR="${SCRIPT_DIR:h}"

SRC_DIR="${SRC:-${HOME}/Games/cs16}"
OUT_DIR="${OUT:-${HOME}/Games/cs16-windows}"
CACHE_DIR="${CACHE:-${HOME}/Games/.cache/cs16-windows}"

ENGINE_URL="https://github.com/FWGS/xash3d-fwgs/releases/download/continuous/xash3d-fwgs-win32-i386.7z"
CLIENT_URL="https://github.com/Velaron/cs16-client/releases/download/continuous/CS16Client-Windows-X86.zip"

SLIM=0
MAKE_ZIP=0
REFRESH=0
FORCE=0

usage() {
  cat <<'EOF'
Usage: build.sh [options]

Options:
  --slim       skip the Half-Life valve/ assets (~430 MB); the engine's own
               valve/extras.pk3 is kept, which is all CS itself needs
  --zip        also produce <out>.zip next to the output folder
  --refresh    re-download the engine/client archives instead of using the cache
  --force      overwrite an existing output folder
  -h, --help   show this help

Environment:
  SRC=<dir>    source install to take assets from (default ~/Games/cs16)
  OUT=<dir>    output folder            (default ~/Games/cs16-windows)
  CACHE=<dir>  download cache           (default ~/Games/.cache/cs16-windows)
EOF
}

while (( $# )); do
  case "$1" in
    --slim) SLIM=1 ;;
    --zip) MAKE_ZIP=1 ;;
    --refresh) REFRESH=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "error: unknown option '$1'"; usage >&2; exit 2 ;;
  esac
  shift
done

info() { print -P "%F{cyan}==>%f $*"; }
die()  { print -P "%F{red}error:%f $*" >&2; exit 1; }

for tool in curl 7z unzip rsync; do
  (( $+commands[$tool] )) || die "'$tool' not found — install it first (brew install p7zip rsync)"
done

[[ -d "$SRC_DIR/cstrike" ]] || die "no cstrike/ in ${SRC_DIR} — set SRC=<dir> to your CS 1.6 install"

if [[ -e "$OUT_DIR" ]]; then
  (( FORCE )) || die "${OUT_DIR} already exists — pass --force to overwrite"
  info "Removing existing ${OUT_DIR}"
  rm -rf "$OUT_DIR"
fi

# --- 1. download -------------------------------------------------------------

mkdir -p "$CACHE_DIR"
ENGINE_ARCHIVE="${CACHE_DIR}/xash3d-fwgs-win32-i386.7z"
CLIENT_ARCHIVE="${CACHE_DIR}/CS16Client-Windows-X86.zip"

fetch() {
  local url="$1" dest="$2"
  if [[ -s "$dest" ]] && (( ! REFRESH )); then
    info "Using cached ${dest:t}"
    return
  fi
  info "Downloading ${dest:t}"
  curl -fL --progress-bar -o "${dest}.part" "$url"
  mv "${dest}.part" "$dest"
}

fetch "$ENGINE_URL" "$ENGINE_ARCHIVE"
fetch "$CLIENT_URL" "$CLIENT_ARCHIVE"

# --- 2. engine + client ------------------------------------------------------

mkdir -p "$OUT_DIR"

info "Extracting the Xash3D FWGS engine"
7z x -bso0 -bsp0 -o"$OUT_DIR" "$ENGINE_ARCHIVE"

info "Extracting CS16Client over it"
unzip -q -o "$CLIENT_ARCHIVE" -d "$OUT_DIR"

# Debug symbols and import libraries are ~180 MB of the two archives and are of
# no use to a player.
find "$OUT_DIR" \( -name '*.pdb' -o -name '*.lib' \) -delete

[[ -f "$OUT_DIR/xash3d.exe" ]]              || die "xash3d.exe missing after extraction"
[[ -f "$OUT_DIR/cstrike/dlls/mp.dll" ]]     || die "CS16Client mp.dll missing after extraction"

# --- 3. game assets ----------------------------------------------------------

# --ignore-existing is the important flag: every file the engine or CS16Client
# already placed wins over the one from the source install, so the WaRzOnE
# client.dll / mp.dll never overwrite the CS16Client ones.
#
# Excluded on purpose:
#   *.dylib, SDL2.framework  — macOS binaries from the local install
#   addons/                  — Metamod / AMX Mod X / dproto, none load on Xash3D
#   bin/                     — Valve TrackerUI, unused by this engine
#   cl_dlls/GameUI.dll       — Valve's VGUI menu; CS16Client ships its own
#   config/video/opengl.cfg  — machine-specific, let Windows regenerate them
#   cache, logs, SAVE, ...   — local state, not content
COMMON_EXCLUDES=(
  --exclude '*.dylib'
  --exclude 'SDL2.framework/'
  --exclude '*.orig-*'
  --exclude '*.bak'
  --exclude 'addons/'
  --exclude 'cache/'
  --exclude 'logs/'
  --exclude 'SAVE/'
  --exclude 'config.cfg'
  --exclude 'video.cfg'
  --exclude 'opengl.cfg'
  --exclude 'console_history.txt'
  --exclude 'custom.hpk'
  --exclude 'tempdecal.wad'
  --exclude 'voice_ban.dt'
  --exclude '.DS_Store'
)

info "Copying cstrike/ assets from ${SRC_DIR}"
rsync -a --ignore-existing "${COMMON_EXCLUDES[@]}" \
  --exclude 'bin/' \
  --exclude 'cl_dlls/GameUI.dll' \
  "$SRC_DIR/cstrike/" "$OUT_DIR/cstrike/"

if (( SLIM )); then
  info "Skipping valve/ assets (--slim) — keeping the engine's valve/extras.pk3"
else
  info "Copying valve/ assets from ${SRC_DIR}"
  rsync -a --ignore-existing "${COMMON_EXCLUDES[@]}" \
    "$SRC_DIR/valve/" "$OUT_DIR/valve/"
fi

# --- 4. configuration --------------------------------------------------------

# On Windows the CS game module is cstrike/dlls/mp.dll — the macOS install
# points at dlls\cs.dll instead, which is the CS16Client name for its arm64
# dylib. Pointing it anywhere else (e.g. the WaRzOnE metamod.dll) makes the
# server side fail to initialise and greys out "Create Server".
#
# liblist.gam has CRLF line endings, so the substitution stops at the closing
# quote instead of anchoring to end-of-line — that leaves the \r in place.
LIBLIST="$OUT_DIR/cstrike/liblist.gam"
if [[ -f "$LIBLIST" ]]; then
  info "Pointing liblist.gam at the Windows game module"
  perl -0pi -e 's/^gamedll\s+"[^"]*"/gamedll "dlls\\mp.dll"/m' "$LIBLIST"
  grep -q 'gamedll "dlls\\mp.dll"' "$LIBLIST" || die "failed to rewrite gamedll in ${LIBLIST}"
else
  die "cstrike/liblist.gam is missing from the source install"
fi

# Bots: same mechanism as the macOS launcher — the repo's bots.cfg is the source
# of truth and listenserver.cfg execs it on every map start.
info "Installing bots.cfg"
cp "$REPO_GAME_DIR/bots.cfg" "$OUT_DIR/cstrike/bots.cfg"

LISTENSERVER="$OUT_DIR/cstrike/listenserver.cfg"
if [[ -f "$LISTENSERVER" ]] && ! grep -q '^exec bots.cfg' "$LISTENSERVER"; then
  # CRLF, to match the rest of the file.
  printf '\r\n// bot settings (installed by games/counter-strike/windows/build.sh)\r\nexec bots.cfg\r\n' \
    >> "$LISTENSERVER"
fi

# --- 5. launchers and notes --------------------------------------------------

# Windows batch files get CRLF line endings; some Windows setups mis-parse a
# .bat that uses bare LF.
write_crlf() {
  sed -e 's/$/\r/' > "$1"
}

info "Writing play.bat / play-offline.bat / dedicated-server.bat"

write_crlf "$OUT_DIR/play.bat" <<'EOF'
@echo off
rem Start Counter-Strike 1.6 on the Xash3D FWGS engine.
rem Extra arguments are passed straight to the engine, e.g.:
rem   play.bat -windowed
cd /d "%~dp0"
start "" xash3d.exe -console -game cstrike %*
EOF

write_crlf "$OUT_DIR/play-offline.bat" <<'EOF'
@echo off
rem Start straight into an offline match against bots.
rem   play-offline.bat            -> de_dust2
rem   play-offline.bat cs_office  -> that map instead
rem Bot settings live in cstrike\bots.cfg.
cd /d "%~dp0"
set "MAP=%~1"
if "%MAP%"=="" set "MAP=de_dust2"
start "" xash3d.exe -console -game cstrike +map %MAP%
EOF

write_crlf "$OUT_DIR/dedicated-server.bat" <<'EOF'
@echo off
rem Headless server on UDP 27015. Only Xash3D / CS16Client clients can join it,
rem and it has NO bots (the game module refuses them on a dedicated server).
rem   dedicated-server.bat              -> de_dust2, 12 slots
rem   dedicated-server.bat cs_office 16 -> that map, 16 slots
cd /d "%~dp0"
set "MAP=%~1"
set "SLOTS=%~2"
if "%MAP%"=="" set "MAP=de_dust2"
if "%SLOTS%"=="" set "SLOTS=12"
xash3d.exe -dedicated -console -game cstrike -port 27015 +maxplayers %SLOTS% +map %MAP%
EOF

write_crlf "$OUT_DIR/README.txt" <<'EOF'
Counter-Strike 1.6 on Xash3D FWGS - portable Windows build
==========================================================

No installation, no Steam. Copy this whole folder anywhere on the PC and run:

  play.bat            - start the game (add -windowed for windowed mode)
  play-offline.bat    - jump straight into a match against 8 bots
  dedicated-server.bat- headless LAN server on UDP 27015 (no bots)

Requirements
------------
* Windows 7 or newer, 64-bit is fine - the binaries are 32-bit x86.
* Microsoft Visual C++ Redistributable (x86). If the game refuses to start with
  a missing-DLL error such as VCRUNTIME140.dll, install the x86 package from
  https://aka.ms/vs/17/release/vc_redist.x86.exe and try again.
* Do not put the folder in C:\Program Files - the engine writes its configs and
  screenshots next to the executable. A path such as C:\Games\cs16 is ideal.

Bots
----
An offline match gets 8 bots automatically: cstrike\listenserver.cfg execs
cstrike\bots.cfg on every map start. Edit bots.cfg to change the defaults, or
use the console (press ~):

  bot_quota 8        keep 8 bots on the server (0 = none)
  bot_add            add one bot
  bot_kick           kick all bots (set bot_quota 0 first, or they come back)
  bot_difficulty 2   0 easy, 1 normal, 2 hard, 3 expert
  bot_knives_only    restrict bot weapons (also *_pistols_only, *_snipers_only)

These are the CZ bots built into the ReGameDLL game module - no Metamod, no
YaPB. They use the maps\<map>.nav meshes shipped with this build.

Notes
-----
* Metamod, AMX Mod X and dproto from the original install are NOT included:
  they do not load on Xash3D. Admin/stats plugins are therefore unavailable.
* Multiplayer: Xash3D speaks GoldSrc protocol 48 well enough for most community
  servers, but servers with strict anti-cheat may reject a non-GoldSrc client.
* Configs are generated on first run, so the first start is the slow one.

See BUILD_INFO.txt for exactly which engine and client builds this package was
assembled from.
EOF

info "Writing BUILD_INFO.txt"
{
  print "Counter-Strike 1.6 / Xash3D FWGS - Windows x86 package"
  print "Assembled: $(date -u '+%Y-%m-%dT%H:%M:%SZ') on $(sw_vers -productName) $(sw_vers -productVersion)"
  print "Built by:  games/counter-strike/windows/build.sh"
  print ""
  print "Engine:    ${ENGINE_URL}"
  print "           sha256 $(shasum -a 256 "$ENGINE_ARCHIVE" | cut -d' ' -f1)"
  print "Client:    ${CLIENT_URL}"
  print "           sha256 $(shasum -a 256 "$CLIENT_ARCHIVE" | cut -d' ' -f1)"
  print "Assets:    ${SRC_DIR}$( (( SLIM )) && print ' (cstrike only, --slim)' || print ' (cstrike + valve)')"
  print ""
  print "Both engine and client come from rolling 'continuous' tags, so the same"
  print "URLs will serve different binaries later - the hashes above identify"
  print "this build."
} > "$OUT_DIR/BUILD_INFO.txt"

# --- 6. package --------------------------------------------------------------

if (( MAKE_ZIP )); then
  ZIP_PATH="${OUT_DIR}.zip"
  info "Zipping to ${ZIP_PATH}"
  rm -f "$ZIP_PATH"
  (cd "${OUT_DIR:h}" && zip -qr9 "${ZIP_PATH:t}" "${OUT_DIR:t}" -x '*.DS_Store')
fi

info "Done: ${OUT_DIR} ($(du -sh "$OUT_DIR" | cut -f1))"
(( MAKE_ZIP )) && info "Archive: ${OUT_DIR}.zip ($(du -sh "${OUT_DIR}.zip" | cut -f1))"
print "Copy it to the Windows machine and run play.bat."
