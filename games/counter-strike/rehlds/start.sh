#!/usr/bin/env bash
# Start the CS 1.6 ReHLDS dedicated server.
#
# Environment overrides:
#   SERVER_DIR=~/cs16-server   installation directory
#   MAP=de_dust2               first map
#   MAXPLAYERS=16              slot count (bots take slots too)
#   PORT=27015                 UDP port
#   CFG_OVERRIDE_DIR=/path     *.cfg copied into cstrike/ before launch (Docker)
#   HLDS_EXTRA_ARGS="-norestart"
#
# Anything passed on the command line is appended to the hlds_run arguments.

set -euo pipefail

SERVER_DIR="${SERVER_DIR:-${HOME}/cs16-server}"
MAP="${MAP:-de_dust2}"
MAXPLAYERS="${MAXPLAYERS:-16}"
PORT="${PORT:-27015}"

[[ -x "${SERVER_DIR}/hlds_run" || -x "${SERVER_DIR}/hlds_linux" ]] ||
  { echo "error: no server binary in ${SERVER_DIR} — run install.sh first" >&2; exit 1; }

# Docker mounts the repo's cfg/ read-only; refresh the live configs from it.
if [[ -n "${CFG_OVERRIDE_DIR:-}" && -d "${CFG_OVERRIDE_DIR}" ]]; then
  echo "==> Refreshing configs from ${CFG_OVERRIDE_DIR}"
  # Keep the rcon password install.sh generated — the repo copy only has the
  # placeholder, and copying that in would leave the server without one.
  rcon="$(sed -nE 's/^rcon_password[[:space:]]+"([^"]+)".*/\1/p' \
    "${SERVER_DIR}/cstrike/server.cfg" 2>/dev/null | tail -1)"
  [[ -z "$rcon" || "$rcon" == "__RCON_PASSWORD__" ]] &&
    rcon="${RCON_PASSWORD:-$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 20)}"

  for f in "${CFG_OVERRIDE_DIR}"/*.cfg "${CFG_OVERRIDE_DIR}"/mapcycle.txt; do
    [[ -f "$f" ]] && cp "$f" "${SERVER_DIR}/cstrike/"
  done
  sed -i "s|__RCON_PASSWORD__|${rcon}|" "${SERVER_DIR}/cstrike/server.cfg"
  echo "==> rcon password: ${rcon}"
fi

cd "${SERVER_DIR}"

# hlds_run is Valve's wrapper (sets LD_LIBRARY_PATH, auto-restarts) and only
# comes with the SteamCMD download. A GAME_SRC-seeded install has just the
# ReHLDS binary, so run that directly.
if [[ -x ./hlds_run ]]; then
  RUNNER=(./hlds_run)
else
  export LD_LIBRARY_PATH=".:${SERVER_DIR}:${LD_LIBRARY_PATH:-}"
  RUNNER=(./hlds_linux)
fi

exec "${RUNNER[@]}" \
  -game cstrike \
  -port "${PORT}" \
  -strictportbind \
  +map "${MAP}" \
  +maxplayers "${MAXPLAYERS}" \
  ${HLDS_EXTRA_ARGS:-} \
  "$@"
