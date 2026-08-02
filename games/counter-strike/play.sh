#!/bin/zsh
# Launch Counter-Strike 1.6 on the native Xash3D FWGS engine (no Wine).
#
# This file is installed into the game folder and is self-contained: it resolves
# everything from its own location, so the folder can be renamed, moved to
# another disk or copied to another Mac and still work. Nothing outside the
# folder is needed to play.
#
# Source: games/counter-strike/play.sh in the wine-game repo, copied here by
# install-standalone.sh — edit it there if you still have the repo.
#
# Usage:
#   ./play.sh                 main menu
#   ./play.sh -windowed       any engine flag passes through
#   ./play.sh +map de_dust2   straight into a match against bots
#   BOTS=12 ./play.sh         set the bot count first (see below)

set -euo pipefail

GAME_DIR="${0:A:h}"
CSTRIKE_DIR="${GAME_DIR}/cstrike"

if [[ ! -x "${GAME_DIR}/xash3d" ]]; then
  print -u2 "error: xash3d engine not found in ${GAME_DIR}"
  print -u2 "play.sh has to stay in the game folder, next to the engine."
  exit 1
fi

# BOTS=<n> edits cstrike/bots.cfg in place. That file is the source of truth for
# bot settings and nothing rewrites it behind your back, so the count sticks
# until it is changed again — edit the file directly for anything else.
if [[ -n "${BOTS:-}" ]]; then
  if [[ ! "$BOTS" =~ ^[0-9]+$ ]]; then
    print -u2 "error: BOTS must be a number, got '${BOTS}'"
    exit 1
  fi
  if [[ -f "${CSTRIKE_DIR}/bots.cfg" ]]; then
    sed -i '' -E "s/^bot_quota .*/bot_quota ${BOTS}/" "${CSTRIKE_DIR}/bots.cfg"
  else
    print -u2 "warning: ${CSTRIKE_DIR}/bots.cfg is missing, BOTS=${BOTS} ignored"
  fi
fi

cd "$GAME_DIR"
exec ./xash3d -console -game cstrike "$@"
