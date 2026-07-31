#!/bin/zsh
# Launch Counter-Strike 1.6 natively on Apple Silicon via Xash3D FWGS.
# No Wine involved — see README.md for why the Wine route was abandoned
# and how ~/Games/cs16 was assembled.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
GAME_DIR="${HOME}/Games/cs16"
CSTRIKE_DIR="${GAME_DIR}/cstrike"

if [[ ! -x "${GAME_DIR}/xash3d" ]]; then
  print -P "%F{red}error:%f xash3d engine not found in ${GAME_DIR}" >&2
  print "Assemble it first — see games/counter-strike/README.md (Setup)." >&2
  exit 1
fi

# Install this repo's bots.cfg into the game dir and make the server exec it on
# every map start. BOTS=<n> overrides the bot count for this launch.
sync_bots_cfg() {
  local src="${SCRIPT_DIR}/bots.cfg"
  local dst="${CSTRIKE_DIR}/bots.cfg"
  [[ -f "$src" ]] || return 0

  # Always re-copy: the repo file is the source of truth, so a previous
  # BOTS=<n> override never leaks into the next launch.
  cp "$src" "$dst"

  if [[ -n "${BOTS:-}" ]]; then
    if [[ ! "$BOTS" =~ ^[0-9]+$ ]]; then
      print -P "%F{red}error:%f BOTS must be a number, got '${BOTS}'" >&2
      exit 1
    fi
    sed -i '' -E "s/^bot_quota .*/bot_quota ${BOTS}/" "$dst"
  fi

  # Only listen servers get the bots: on -dedicated the game DLL never registers
  # the bot commands, so server.cfg exec'ing bots.cfg would only print a screen
  # of "Unknown command" warnings (verified 2026-07-31, see README).
  local cfg="${CSTRIKE_DIR}/listenserver.cfg"
  if [[ -f "$cfg" ]] && ! grep -q '^exec bots.cfg' "$cfg"; then
    [[ -f "${cfg}.orig-no-bots" ]] || cp "$cfg" "${cfg}.orig-no-bots"
    print "\n// bot settings (installed by games/counter-strike/run.sh)\nexec bots.cfg" >> "$cfg"
  fi

  # Drop the exec line earlier versions of this script appended to server.cfg.
  local server_cfg="${CSTRIKE_DIR}/server.cfg"
  if [[ -f "$server_cfg" ]] && grep -q '^exec bots.cfg' "$server_cfg"; then
    sed -i '' \
      -e '\|^// bot settings (installed by games/counter-strike/run.sh)$|d' \
      -e '/^exec bots.cfg$/d' \
      "$server_cfg"
  fi
}

sync_bots_cfg

cd "$GAME_DIR"
exec ./xash3d -console -game cstrike "$@"
