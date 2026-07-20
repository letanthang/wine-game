#!/bin/zsh
# Launch standalone (non-Steam) Counter-Strike 1.6 in its Wine prefix.
# Adjust GAME_EXE to where hl.exe was installed (see README.md).

set -euo pipefail

WINE_BIN="/Applications/Wine Stable.app/Contents/Resources/wine/bin"
export WINEPREFIX="${HOME}/wine-prefixes/counter-strike"

# This build ships cstrike.exe, a self-updating launcher (no classic hl.exe).
# It downloads updates (e.g. cstrike_new.exe) into the CURRENT WORKING
# DIRECTORY, so we must cd into the game dir before starting it.
GAME_DIR="${WINEPREFIX}/drive_c/Games/Counter-Strike 1.6"
GAME_EXE="${GAME_DIR}/cstrike.exe"

command -v wine >/dev/null 2>&1 || export PATH="${WINE_BIN}:${PATH}"

if [[ ! -f "$GAME_EXE" ]]; then
  print -P "%F{red}error:%f game exe not found at ${GAME_EXE}" >&2
  print "Install the game first (see games/counter-strike/README.md)," >&2
  print "or fix the GAME_DIR path at the top of this script." >&2
  exit 1
fi

# Wine virtual desktop size; the game runs inside this window
DESKTOP_SIZE="1600x900"

cd "$GAME_DIR"
# The engine crashes at startup when driving the real display
# ("Exception frame is not in stack limits"); a Wine virtual desktop
# avoids that entirely. Extra args pass through to the game.
exec wine explorer "/desktop=cs16,${DESKTOP_SIZE}" "$GAME_EXE" "$@"
