#!/bin/zsh
# Launch Counter-Strike 1.6 from this repo.
#
# The real launcher lives in the game folder as play.sh, installed by
# install-standalone.sh — that copy is self-contained so the game keeps working
# without this repo. This script only forwards to it, so there is one launch
# path rather than two that can drift apart.
#
# No Wine involved — see README.md for why the Wine route was abandoned and how
# ~/Games/cs16 was assembled.

set -euo pipefail

GAME_DIR="${GAME_DIR:-${HOME}/Games/cs16}"
PLAY_SH="${GAME_DIR}/play.sh"

if [[ ! -x "$PLAY_SH" ]]; then
  print -P "%F{red}error:%f no launcher at ${PLAY_SH}" >&2
  print "Run 'make counter-strike-standalone' to install it, or see" >&2
  print "games/counter-strike/README.md (Setup) if the game itself is missing." >&2
  exit 1
fi

# BOTS=<n> is read by play.sh straight from the environment.
exec "$PLAY_SH" "$@"
