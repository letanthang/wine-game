#!/bin/zsh
# Bundle executable for "Counter-Strike 1.6.app" — what a double-click runs.
#
# Finder gives this process no terminal and cwd `/`, so everything is logged to
# ~/Library/Logs/counter-strike-16.log and hard failures are reported through a
# Finder alert. Launching itself is play.sh's job; this is only the wrapper.
#
# The file is static: the game folder is derived from the bundle's own path, and
# the optional map to boot into comes from Contents/Resources/launch-args. That
# is what lets the whole game folder be moved or copied to another Mac.
#
# Source: games/counter-strike/app-launcher.sh in the wine-game repo, installed
# here by install-standalone.sh.

CONTENTS_DIR="${0:A:h:h}"        # …/Contents
GAME_DIR="${CONTENTS_DIR:h:h}"   # the folder the .app sits in

LOG="${HOME}/Library/Logs/counter-strike-16.log"

alert() {
  osascript -e "display alert \"Counter-Strike 1.6\" message \"$1\" as critical" \
    >/dev/null 2>&1 || true
}

mkdir -p "${LOG:h}"
# One launch per log file, so it never grows without bound.
print -- "=== $(date '+%Y-%m-%d %H:%M:%S') launch ===" > "$LOG"
exec >>"$LOG" 2>&1

# Normal case: the app sits in the game folder. If it was moved out (dragged
# into /Applications, say), fall back to the path recorded at install time.
if [[ ! -x "${GAME_DIR}/play.sh" ]]; then
  recorded="${CONTENTS_DIR}/Resources/game-dir"
  if [[ -f "$recorded" ]]; then
    print -- "not in a game folder, using the recorded path"
    GAME_DIR="$(cat "$recorded")"
  fi
fi

launch_args=()
args_file="${CONTENTS_DIR}/Resources/launch-args"
[[ -f "$args_file" ]] && launch_args=(${=$(cat "$args_file")})

print -- "game dir: ${GAME_DIR}"

if [[ -x "${GAME_DIR}/play.sh" ]]; then
  exec "${GAME_DIR}/play.sh" "${launch_args[@]}"
fi

# play.sh is gone but the engine may still be there — start it directly rather
# than refuse to launch. This loses the BOTS= handling, nothing else.
if [[ -x "${GAME_DIR}/xash3d" ]]; then
  print -- "warning: play.sh is missing, launching the engine directly"
  cd "$GAME_DIR"
  exec ./xash3d -console -game cstrike "${launch_args[@]}"
fi

alert "No Counter-Strike install found at ${GAME_DIR}. Keep this app inside the game folder, next to xash3d and play.sh."
exit 1
