#!/bin/zsh
# Assemble a ready-to-play macOS arm64 build of Counter-Strike 1.6 on Xash3D
# FWGS, the way windows/build.sh does it for Windows.
#
# The package is three parts glued together:
#   1. Xash3D FWGS engine  — apple-arm64 build from the rolling `continuous` tag
#   2. CS16Client          — macOS arm64 build (client/menu/cs/yapb dylibs)
#   3. Game assets         — copied from a local install (default ~/Games/assets)
#
# The asset source is a plain CS 1.6 install: only its cstrike/ and valve/
# folders are read, and only for files the engine and CS16Client did not already
# provide, so the arm64 binaries always win over whatever the source carries.
#
# By default the finished folder is then handed to install-standalone.sh, which
# adds play.sh, README.txt, bots.cfg and the double-clickable .app.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_GAME_DIR="${SCRIPT_DIR:h}"

SRC_DIR="${SRC:-${HOME}/Games/assets}"
OUT_DIR="${OUT:-${HOME}/Games/cs16-mac}"
CACHE_DIR="${CACHE:-${HOME}/Games/.cache/cs16-mac}"

ENGINE_URL="https://github.com/FWGS/xash3d-fwgs/releases/download/continuous/xash3d-fwgs-apple-arm64.tar.xz"
CLIENT_URL="https://github.com/Velaron/cs16-client/releases/download/continuous/CS16Client-macOS-arm64.zip"

SLIM=0
REFRESH=0
FORCE=0
STANDALONE=1

usage() {
  cat <<'EOF'
Usage: build.sh [options]

Options:
  --slim            skip the Half-Life valve/ assets (~430 MB); the engine's own
                    valve/extras.pk3 is kept, which is all CS itself needs
  --refresh         re-download the engine/client archives instead of using the cache
  --force           overwrite an existing output folder
  --no-standalone   stop after assembling; do not run install-standalone.sh
  -h, --help        show this help

Environment:
  SRC=<dir>    install to take assets from (default ~/Games/assets)
  OUT=<dir>    output folder               (default ~/Games/cs16-mac)
  CACHE=<dir>  download cache              (default ~/Games/.cache/cs16-mac)
EOF
}

while (( $# )); do
  case "$1" in
    --slim) SLIM=1 ;;
    --refresh) REFRESH=1 ;;
    --force) FORCE=1 ;;
    --no-standalone) STANDALONE=0 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "error: unknown option '$1'"; usage >&2; exit 2 ;;
  esac
  shift
done

info() { print -P "%F{cyan}==>%f $*"; }
warn() { print -P "%F{yellow}warning:%f $*" >&2; }
die()  { print -P "%F{red}error:%f $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "this build is macOS-only — see windows/build.sh for the Windows package"

for tool in curl tar unzip rsync; do
  (( $+commands[$tool] )) || die "'$tool' not found"
done

[[ -d "$SRC_DIR/cstrike" ]] || die "no cstrike/ in ${SRC_DIR} — set SRC=<dir> to a CS 1.6 install"

if [[ -e "$OUT_DIR" ]]; then
  (( FORCE )) || die "${OUT_DIR} already exists — pass --force to overwrite"
  info "Removing existing ${OUT_DIR}"
  rm -rf "$OUT_DIR"
fi

SRC_DIR="${SRC_DIR:A}"

# --- 1. download -------------------------------------------------------------

mkdir -p "$CACHE_DIR"
ENGINE_ARCHIVE="${CACHE_DIR}/xash3d-fwgs-apple-arm64.tar.xz"
CLIENT_ARCHIVE="${CACHE_DIR}/CS16Client-macOS-arm64.zip"

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

# Both archives unpack flat into the game folder: the engine tarball has a "./"
# root, the client zip a "cstrike/" one.
info "Extracting the Xash3D FWGS engine"
tar -xJf "$ENGINE_ARCHIVE" -C "$OUT_DIR"

info "Extracting CS16Client over it"
unzip -q -o "$CLIENT_ARCHIVE" -d "$OUT_DIR"

[[ -f "$OUT_DIR/xash3d" ]]                        || die "xash3d missing after extraction"
[[ -f "$OUT_DIR/libxash.dylib" ]]                 || die "libxash.dylib missing after extraction"
[[ -f "$OUT_DIR/cstrike/dlls/cs_arm64.dylib" ]]   || die "CS16Client cs_arm64.dylib missing after extraction"

chmod +x "$OUT_DIR/xash3d"

# --- 3. game assets ----------------------------------------------------------

# --ignore-existing is the important flag: every file the engine or CS16Client
# already placed wins over the one from the source install, so a stale
# client_arm64.dylib in the source can never overwrite the freshly downloaded
# one.
#
# Excluded on purpose:
#   *.dll, *.exe             — Windows binaries; nothing on arm64 macOS loads them
#   addons/                  — Metamod / AMX Mod X / dproto, none load on Xash3D
#   bin/                     — Valve TrackerUI, unused by this engine
#   *.dylib                  — only the downloaded arm64 ones belong here
#   bots.cfg                 — install-standalone.sh installs the repo's copy
#   config/video/opengl.cfg  — machine-specific, let the engine regenerate them
#   cache, logs, SAVE, ...   — local state, not content
COMMON_EXCLUDES=(
  --exclude '*.dll'
  --exclude '*.exe'
  --exclude '*.dylib'
  --exclude '*.orig-*'
  --exclude '*.bak'
  --exclude 'addons/'
  --exclude 'cache/'
  --exclude 'logs/'
  --exclude 'SAVE/'
  --exclude 'bots.cfg'
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
  "$SRC_DIR/cstrike/" "$OUT_DIR/cstrike/"

if (( SLIM )); then
  info "Skipping valve/ assets (--slim) — keeping the engine's own valve/"
else
  info "Copying valve/ assets from ${SRC_DIR}"
  rsync -a --ignore-existing "${COMMON_EXCLUDES[@]}" \
    "$SRC_DIR/valve/" "$OUT_DIR/valve/"
fi

# --- 4. configuration --------------------------------------------------------

# The CS game module is cstrike/dlls/cs.dll in liblist.gam; the engine appends
# the platform suffix itself and loads dlls/cs_arm64.dylib. Pointing it anywhere
# else (e.g. the WaRzOnE metamod.dll) makes the server side fail to initialise
# and greys out "Create Server".
#
# liblist.gam has CRLF line endings, so the substitution stops at the closing
# quote instead of anchoring to end-of-line — that leaves the \r in place.
LIBLIST="$OUT_DIR/cstrike/liblist.gam"
[[ -f "$LIBLIST" ]] || die "cstrike/liblist.gam is missing from the source install"

info "Pointing liblist.gam at the CS16Client game module"
perl -0pi -e 's/^gamedll\s+"[^"]*"/gamedll "dlls\\cs.dll"/m' "$LIBLIST"
grep -q 'gamedll "dlls\\cs.dll"' "$LIBLIST" || die "failed to rewrite gamedll in ${LIBLIST}"

# Downloaded archives carry the quarantine flag, and Gatekeeper kills unsigned
# binaries that still have it with no useful message. The same script is
# installed into the game folder, for when it is copied to another Mac.
"${REPO_GAME_DIR}/remove-quarantine.sh" "$OUT_DIR" || \
  warn "could not clear the quarantine flag — run ${REPO_GAME_DIR}/remove-quarantine.sh ${OUT_DIR} by hand"

# --- 5. launcher, bots and the .app ------------------------------------------

if (( STANDALONE )); then
  info "Handing off to install-standalone.sh"
  GAME_DIR="$OUT_DIR" "${REPO_GAME_DIR}/install-standalone.sh"
else
  info "Done: ${OUT_DIR}"
  print "Run install-standalone.sh with GAME_DIR=${OUT_DIR} to add play.sh and the .app."
fi
