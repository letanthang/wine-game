#!/bin/zsh
# Assemble a ready-to-run Debian (Linux) build of Counter-Strike 1.6 on Xash3D
# FWGS.
#
# Runs on this Mac and produces a self-contained folder (optionally a .tar.gz)
# that is copied to a Debian machine and started with play.sh — no installer, no
# Steam, no Wine. See README.md in this directory for the details.
#
# The package is three parts glued together:
#   1. Xash3D FWGS engine  — linux-<arch> build from the rolling `continuous` tag
#   2. CS16Client          — Linux build (client/menu/cs/yapb shared objects)
#   3. Game assets         — copied from the local ~/Games/assets install
#
# Nothing here calls apt: this script never runs on Debian. The one system
# library the package needs there (libfreetype6) is checked for by play.sh on
# the target machine, which prints the apt command instead of running it.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_GAME_DIR="${SCRIPT_DIR:h}"

SRC_DIR="${SRC:-${HOME}/Games/assets}"
OUT_DIR="${OUT:-${HOME}/Games/cs16-debian}"
CACHE_DIR="${CACHE:-${HOME}/Games/.cache/cs16-debian}"

ARCH="amd64"
SLIM=0
MAKE_TAR=0
REFRESH=0
FORCE=0

usage() {
  cat <<'EOF'
Usage: build.sh [options]

Options:
  --arch <arch>  target architecture: amd64 (default) or i386
  --slim         skip the Half-Life valve/ assets (~430 MB); the engine's own
                 valve/extras.pk3 is kept, which is all CS itself needs
  --tar          also produce <out>.tar.gz next to the output folder
  --refresh      re-download the engine/client archives instead of using the cache
  --force        overwrite an existing output folder
  -h, --help     show this help

Environment:
  SRC=<dir>    source install to take assets from (default ~/Games/assets)
  OUT=<dir>    output folder            (default ~/Games/cs16-debian)
  CACHE=<dir>  download cache           (default ~/Games/.cache/cs16-debian)
EOF
}

while (( $# )); do
  case "$1" in
    --arch)
      (( $# >= 2 )) || { print -u2 "error: --arch needs a value"; usage >&2; exit 2; }
      ARCH="$2"
      shift
      ;;
    --slim) SLIM=1 ;;
    --tar) MAKE_TAR=1 ;;
    --refresh) REFRESH=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "error: unknown option '$1'"; usage >&2; exit 2 ;;
  esac
  shift
done

info() { print -P "%F{cyan}==>%f $*"; }
die()  { print -P "%F{red}error:%f $*" >&2; exit 1; }

# The two projects name the same architecture differently, and CS16Client only
# suffixes its libraries on 64-bit: cs_amd64.so there, plain cs.so on i386.
case "$ARCH" in
  amd64) CLIENT_ARCH="x86_64"; LIB_SUFFIX="_amd64" ;;
  i386)  CLIENT_ARCH="i386";   LIB_SUFFIX="" ;;
  arm64) die "CS16Client publishes no Linux arm64 build — only amd64 and i386 can be packaged" ;;
  *)     die "unknown architecture '${ARCH}' — use amd64 or i386" ;;
esac

ENGINE_NAME="xash3d-fwgs-linux-${ARCH}.tar.gz"
CLIENT_NAME="CS16Client-Linux-${CLIENT_ARCH}.tar.gz"
ENGINE_URL="https://github.com/FWGS/xash3d-fwgs/releases/download/continuous/${ENGINE_NAME}"
CLIENT_URL="https://github.com/Velaron/cs16-client/releases/download/continuous/${CLIENT_NAME}"

for tool in curl tar rsync perl; do
  (( $+commands[$tool] )) || die "'$tool' not found"
done

[[ -d "$SRC_DIR/cstrike" ]] || die "no cstrike/ in ${SRC_DIR} — set SRC=<dir> to your CS 1.6 install"

for f in play.sh game-readme.txt; do
  [[ -f "${SCRIPT_DIR}/${f}" ]] || die "${f} is missing next to this script"
done

if [[ -e "$OUT_DIR" ]]; then
  (( FORCE )) || die "${OUT_DIR} already exists — pass --force to overwrite"
  info "Removing existing ${OUT_DIR}"
  rm -rf "$OUT_DIR"
fi

# --- 1. download -------------------------------------------------------------

mkdir -p "$CACHE_DIR"
ENGINE_ARCHIVE="${CACHE_DIR}/${ENGINE_NAME}"
CLIENT_ARCHIVE="${CACHE_DIR}/${CLIENT_NAME}"

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

# The engine tarball wraps everything in an xash3d-fwgs-linux-<arch>/ folder;
# the client tarball has a "cstrike/" root and unpacks flat over it.
info "Extracting the Xash3D FWGS engine (${ARCH})"
tar -xzf "$ENGINE_ARCHIVE" -C "$OUT_DIR" --strip-components 1

info "Extracting CS16Client over it"
tar -xzf "$CLIENT_ARCHIVE" -C "$OUT_DIR"

# AppImage scaffolding: AppRun only works with $APPDIR set, and would be the
# first thing someone tries to run instead of play.sh.
rm -f "$OUT_DIR/AppRun" "$OUT_DIR/.DirIcon" "$OUT_DIR/xash3d-fwgs.desktop"

[[ -f "$OUT_DIR/xash3d" ]]                              || die "xash3d missing after extraction"
[[ -f "$OUT_DIR/libxash.so" ]]                          || die "libxash.so missing after extraction"
[[ -f "$OUT_DIR/cstrike/dlls/cs${LIB_SUFFIX}.so" ]]     || die "CS16Client cs${LIB_SUFFIX}.so missing after extraction"

chmod +x "$OUT_DIR/xash3d"

# --- 3. game assets ----------------------------------------------------------

# --ignore-existing is the important flag: every file the engine or CS16Client
# already placed wins over the one from the source install.
#
# Excluded on purpose:
#   *.dll, *.exe             — Windows binaries; nothing on Linux loads them
#   *.dylib                  — macOS binaries from the local install
#   *.so                     — only the downloaded ones belong here
#   addons/                  — Metamod / AMX Mod X / dproto, none load on Xash3D
#   bin/                     — Valve TrackerUI, unused by this engine
#   bots.cfg                 — the repo's copy is installed below
#   config/video/opengl.cfg  — machine-specific, let the engine regenerate them
#   cache, logs, SAVE, ...   — local state, not content
COMMON_EXCLUDES=(
  --exclude '*.dll'
  --exclude '*.exe'
  --exclude '*.dylib'
  --exclude '*.so'
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
  info "Skipping valve/ assets (--slim) — keeping the engine's valve/extras.pk3"
else
  info "Copying valve/ assets from ${SRC_DIR}"
  rsync -a --ignore-existing "${COMMON_EXCLUDES[@]}" \
    "$SRC_DIR/valve/" "$OUT_DIR/valve/"
fi

# --- 4. configuration --------------------------------------------------------

# Same value as the macOS build: the engine turns dlls\cs.dll into the
# platform's own name, dlls/cs_amd64.so or dlls/cs.so here. Pointing it anywhere
# else (e.g. the WaRzOnE metamod.dll) makes the server side fail to initialise
# and greys out "Create Server". A gamedll_linux line, if the source install has
# one, would take precedence on Linux, so it is rewritten too.
#
# liblist.gam has CRLF line endings, so the substitutions stop at the closing
# quote instead of anchoring to end-of-line — that leaves the \r in place.
LIBLIST="$OUT_DIR/cstrike/liblist.gam"
[[ -f "$LIBLIST" ]] || die "cstrike/liblist.gam is missing from the source install"

info "Pointing liblist.gam at the CS16Client game module"
perl -0pi -e 's/^gamedll\s+"[^"]*"/gamedll "dlls\\cs.dll"/m; s/^gamedll_linux\s+"[^"]*"/gamedll_linux "dlls\/cs.so"/m' "$LIBLIST"
grep -q 'gamedll "dlls\\cs.dll"' "$LIBLIST" || die "failed to rewrite gamedll in ${LIBLIST}"

# Bots: same mechanism as the other builds — the repo's bots.cfg is the source
# of truth and listenserver.cfg execs it on every map start.
info "Installing bots.cfg"
install -m 644 "$REPO_GAME_DIR/bots.cfg" "$OUT_DIR/cstrike/bots.cfg"

LISTENSERVER="$OUT_DIR/cstrike/listenserver.cfg"
if [[ -f "$LISTENSERVER" ]] && ! grep -q '^exec bots.cfg' "$LISTENSERVER"; then
  print "\n// bot settings (installed by games/counter-strike/debian/build.sh)\nexec bots.cfg" >> "$LISTENSERVER"
fi

# --- 5. launcher and notes ---------------------------------------------------

info "Installing play.sh and README.txt"
install -m 755 "${SCRIPT_DIR}/play.sh" "$OUT_DIR/play.sh"
install -m 644 "${SCRIPT_DIR}/game-readme.txt" "$OUT_DIR/README.txt"

info "Writing BUILD_INFO.txt"
{
  print "Counter-Strike 1.6 / Xash3D FWGS - Linux ${ARCH} package"
  print "Assembled: $(date -u '+%Y-%m-%dT%H:%M:%SZ') on $(sw_vers -productName) $(sw_vers -productVersion)"
  print "Built by:  games/counter-strike/debian/build.sh"
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

# A tarball rather than a zip: the engine folder relies on symlinks
# (libSDL2-2.0.so.0 -> libSDL2-2.0.so.0.3200.10, ...) and on executable bits,
# and tar is what carries both across reliably. COPYFILE_DISABLE stops macOS
# tar from adding ._* AppleDouble entries.
if (( MAKE_TAR )); then
  TAR_PATH="${OUT_DIR}.tar.gz"
  info "Packing ${TAR_PATH}"
  rm -f "$TAR_PATH"
  COPYFILE_DISABLE=1 tar -czf "$TAR_PATH" --exclude '.DS_Store' -C "${OUT_DIR:h}" "${OUT_DIR:t}"
fi

info "Done: ${OUT_DIR} ($(du -sh "$OUT_DIR" | cut -f1))"
(( MAKE_TAR )) && info "Archive: ${OUT_DIR}.tar.gz ($(du -sh "${OUT_DIR}.tar.gz" | cut -f1))"
print "Copy it to the Debian machine and run ./play.sh."
