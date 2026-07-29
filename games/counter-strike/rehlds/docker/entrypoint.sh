#!/usr/bin/env bash
# Container entrypoint.
#
# The server is baked into the image at build time, so this normally just fills
# in the per-deployment secrets and launches it. The install fallback only fires
# when the server directory has been replaced by an empty volume.
#
# Secrets (never baked into the image — see NO_SECRETS in install.sh):
#   RCON_PASSWORD=...   fixed rcon password; random per start if unset
#   REUNION_SALT=...    ReUnion SteamIdHashSalt; random per start if unset.
#                       Set it, or players' generated SteamIDs change on every
#                       container recreation (AMXX admin entries stop matching).

set -euo pipefail

SERVER_DIR="${SERVER_DIR:-/opt/cs16-server}"
SETUP_DIR="${SETUP_DIR:-/opt/rehlds-setup}"

random_string() { head -c "${1:-24}" /dev/urandom | base64 | tr -d '/+=' | head -c "${2:-20}"; }

if [[ ! -f "${SERVER_DIR}/cstrike/dlls/cs.so" ]]; then
  echo "==> ${SERVER_DIR} is empty (mounted volume?) — installing the server now"
  SKIP_DEPS=1 "${SETUP_DIR}/install.sh"
fi

fill_secrets() {
  local server_cfg="${SERVER_DIR}/cstrike/server.cfg"
  local reunion_cfg="${SERVER_DIR}/cstrike/reunion.cfg"

  if [[ -f "$server_cfg" ]] && grep -q '__RCON_PASSWORD__' "$server_cfg"; then
    local rcon="${RCON_PASSWORD:-$(random_string 24 20)}"
    sed -i "s|__RCON_PASSWORD__|${rcon}|" "$server_cfg"
    if [[ -n "${RCON_PASSWORD:-}" ]]; then
      echo "==> rcon password taken from \$RCON_PASSWORD"
    else
      echo "==> rcon password (random for this run): ${rcon}"
    fi
  fi

  if [[ -f "$reunion_cfg" ]] && grep -q '__STEAMID_HASH_SALT__' "$reunion_cfg"; then
    local salt="${REUNION_SALT:-$(random_string 48 40)}"
    sed -i "s|__STEAMID_HASH_SALT__|${salt}|" "$reunion_cfg"
    [[ -n "${REUNION_SALT:-}" ]] ||
      echo "==> ReUnion salt is random for this run; set \$REUNION_SALT to keep SteamIDs stable"
  fi
}

fill_secrets

exec "${SETUP_DIR}/start.sh" "$@"
