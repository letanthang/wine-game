#!/bin/zsh
# Launch Counter-Strike 1.6 natively on Apple Silicon via Xash3D FWGS.
# No Wine involved — see README.md for why the Wine route was abandoned
# and how ~/Games/cs16 was assembled.

set -euo pipefail

GAME_DIR="${HOME}/Games/cs16"

if [[ ! -x "${GAME_DIR}/xash3d" ]]; then
  print -P "%F{red}error:%f xash3d engine not found in ${GAME_DIR}" >&2
  print "Assemble it first — see games/counter-strike/README.md (Setup)." >&2
  exit 1
fi

cd "$GAME_DIR"
exec ./xash3d -game cstrike "$@"
