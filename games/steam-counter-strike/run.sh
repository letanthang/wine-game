#!/bin/zsh
# Launch Counter-Strike 1.6 via its Sikarugir wrapper.
# The wrapper (with Steam + CS 1.6 inside) must exist first — see README.md.
# Adjust WRAPPER if Sikarugir created the wrapper somewhere else.

set -euo pipefail

WRAPPER="${HOME}/Applications/Sikarugir/Counter-Strike.app"

if [[ ! -d "$WRAPPER" ]]; then
  print -P "%F{red}error:%f wrapper not found at ${WRAPPER}" >&2
  print "Create it first — see games/steam-counter-strike/README.md (Setup)." >&2
  exit 1
fi

exec open "$WRAPPER"
