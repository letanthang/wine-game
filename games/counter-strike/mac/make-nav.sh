#!/bin/zsh
# Generate the maps/<map>.nav navigation mesh a map needs before the CZ bots can
# play it.
#
# Map archives almost never ship a .nav, and without one the game prints
# "ERROR: Failed to load 'maps/<map>.nav' file navigation map!" on every map
# start and the bots never join. The mesh has to be computed by the game itself:
# ReGameDLL's `bot_nav_analyze` samples the walkable space, merges and connects
# the areas, then works out approach points and hiding spots — the "Learning
# map" screen — and writes the .nav at the end.
#
# It cannot be driven with `+bot_nav_analyze` on the command line: `+` commands
# run during init, before the map is up, and the command is silently dropped.
# So the command is appended to cstrike/listenserver.cfg, which the engine execs
# *after* each map load, and taken out again afterwards. The original file is
# restored even if this script is interrupted.
#
# The finished .nav is copied back into the asset source as well, so the next
# `make counter-strike-mac ARGS=--force` keeps it. Analysis takes anywhere from
# seconds on an aim map to several minutes on a large one, and needs a window —
# a dedicated server registers no bot commands at all.
#
# Usage:
#   ./make-nav.sh cs_mansion
#   ./make-nav.sh --timeout 900 cs_mansion aim_ak-colt
#
# Re-running regenerates: an existing .nav is only replaced once the new one is
# written.

set -euo pipefail

GAME_DIR="${GAME:-${HOME}/Games/cs16-mac}"
SRC_DIR="${SRC:-${HOME}/Games/assets}"
TIMEOUT=600

usage() {
  cat <<'EOF'
Usage: make-nav.sh [options] <map-name>...

Options:
  --timeout <sec>  give up on one map after this long (default 600)
  --game <dir>     build to run          (default ~/Games/cs16-mac)
  --src <dir>      asset source to copy the .nav back into (default ~/Games/assets)
  -h, --help       show this help
EOF
}

maps=()
while (( $# )); do
  case "$1" in
    --timeout) shift; TIMEOUT="${1:-}" ;;
    --game) shift; GAME_DIR="${1:-}" ;;
    --src) shift; SRC_DIR="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    -*) print -u2 "error: unknown option '$1'"; usage >&2; exit 2 ;;
    *) maps+=("$1") ;;
  esac
  shift
done

info() { print -P -r "%F{cyan}==>%f $*"; }
warn() { print -P -r "%F{yellow}warning:%f $*" >&2; }
die()  { print -P -r "%F{red}error:%f $*" >&2; exit 1; }

(( ${#maps} )) || { usage >&2; exit 2 }

# Run this from a real terminal. play.sh passes -console, so the engine reads
# console commands from stdin; when stdin is not a tty it issues `quit` to itself
# about fifteen seconds in ("Issuing host shutdown due to reason \"command\""),
# which is long before any analysis finishes. Driving this from a background
# shell, a CI job or `nohup` therefore fails in a way that looks like the
# analysis silently doing nothing.
[[ -t 0 ]] || die "stdin is not a terminal — run this from a terminal, not from a background job (the engine quits on its own otherwise)"

[[ "$TIMEOUT" == <-> ]] || die "--timeout takes a number of seconds"
[[ -x "${GAME_DIR}/play.sh" ]] || die "no play.sh in ${GAME_DIR}"

GAME_DIR="${GAME_DIR:A}"
CSTRIKE="${GAME_DIR}/cstrike"
LISTENSERVER="${CSTRIKE}/listenserver.cfg"
[[ -f "$LISTENSERVER" ]] || die "${LISTENSERVER} is missing"

BACKUP="${LISTENSERVER}.pre-nav"

# The config must go back exactly as it was, however this script ends: leaving
# bot_nav_analyze in listenserver.cfg would restart the analysis on every single
# map load from then on.
restore_cfg() {
  if [[ -f "$BACKUP" ]]; then
    mv -f "$BACKUP" "$LISTENSERVER"
  fi
}
trap 'stop_engine; restore_cfg; exit 130' INT TERM
trap 'restore_cfg' EXIT

# play.sh ends in `exec ./xash3d`, so the pid of the launched job is the engine
# itself. Matching by name instead does not work: the engine's command line is
# the relative "./xash3d", so neither the game directory nor an absolute path
# appears in it, and a pgrep for either finds nothing while the game is running.
engine_pid=0

engine_alive() { (( engine_pid )) && kill -0 "$engine_pid" 2>/dev/null }

stop_engine() {
  engine_alive && kill "$engine_pid" 2>/dev/null
  # The engine writes the .nav on its way out of the analysis, so give it a
  # moment before the file is checked or moved.
  sleep 2
  engine_pid=0
}

for map in $maps; do
  [[ -f "${CSTRIKE}/maps/${map}.bsp" ]] || die "no maps/${map}.bsp in ${CSTRIKE} — add the map first (add-map.sh ${map})"

  nav="${CSTRIKE}/maps/${map}.nav"
  log="${TMPDIR:-/tmp}/cs16-nav-${map}.log"

  info "Analyzing ${map} (up to ${TIMEOUT}s; a window opens, leave it alone)"

  cp "$LISTENSERVER" "$BACKUP"
  # sv_cheats first: most bot_nav_* commands are cheat-protected and are
  # rejected without a word when it is off.
  print -- "\n// temporary, added by make-nav.sh\nsv_cheats 1\nbot_nav_analyze" >> "$LISTENSERVER"

  # A pre-existing mesh must not be mistaken for the new one.
  had_nav=0
  if [[ -f "$nav" ]]; then
    had_nav=1
    mv "$nav" "${nav}.previous"
  fi

  ( cd "$GAME_DIR" && exec ./play.sh -windowed +map "$map" >"$log" 2>&1 ) &
  engine_pid=$!

  waited=0
  while (( waited < TIMEOUT )); do
    sleep 5
    waited=$(( waited + 5 ))
    [[ -f "$nav" ]] && break
    # If the engine died there is nothing left to wait for.
    engine_alive || break
  done

  stop_engine
  restore_cfg

  if [[ -f "$nav" ]]; then
    rm -f "${nav}.previous"
    info "Wrote maps/${map}.nav ($(du -h "$nav" | cut -f1 | tr -d ' ')) after ${waited}s"

    if [[ -d "${SRC_DIR}/cstrike/maps" ]]; then
      cp "$nav" "${SRC_DIR}/cstrike/maps/${map}.nav"
      info "Copied into ${SRC_DIR}/cstrike/maps so rebuilds keep it"
    fi
  else
    (( had_nav )) && mv "${nav}.previous" "$nav"
    warn "no .nav after ${waited}s — last lines of ${log}:"
    sed -e 's/\x1b\[[0-9;]*m//g' "$log" | tail -5 >&2
    die "analysis did not finish for ${map}"
  fi
done

info "Done"
