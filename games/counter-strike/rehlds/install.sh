#!/usr/bin/env bash
# Install a Counter-Strike 1.6 dedicated server on Debian, built on the ReHLDS
# stack (ReHLDS + ReGameDLL_CS + Metamod-R + ReUnion + AMX Mod X + zBot).
#
# This script runs ON THE DEBIAN SERVER, not on macOS — the rest of this repo
# is macOS/zsh, this one is Linux/bash on purpose.
#
# Safe to re-run: every step is skipped or refreshed idempotently, and
# generated secrets (rcon password, ReUnion salt) are preserved.
#
# Environment overrides:
#   SERVER_DIR=~/cs16-server   where the server is installed
#   STEAMCMD_DIR=~/steamcmd    where SteamCMD lives
#   SKIP_DEPS=1                do not touch apt (deps already present)
#   SKIP_GPG=1                 do not verify release signatures (not advised)
#   NAV_SRC=/path/to/maps      copy *.nav from here if the game files have none
#   GAME_SRC=/path/to/hlds     take the game files from an existing HLDS install
#                              instead of downloading them with SteamCMD

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "${SCRIPT_DIR}/versions.env"

SERVER_DIR="${SERVER_DIR:-${HOME}/cs16-server}"
STEAMCMD_DIR="${STEAMCMD_DIR:-${HOME}/steamcmd}"
CSTRIKE_DIR="${SERVER_DIR}/cstrike"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

log()  { printf '\033[32m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  SUDO=""
fi

fetch() {  # fetch <dest> <url>
  log "Downloading $(basename "$2")"
  curl -fsSL --retry 3 --retry-delay 2 -o "$1" "$2"
}

# 1. Sanity checks ---------------------------------------------------------
[[ -f /etc/debian_version ]] || warn "This is not a Debian-like system; package install may fail."

# 2. Dependencies ----------------------------------------------------------
install_deps() {
  if [[ -n "${SKIP_DEPS:-}" ]]; then
    log "SKIP_DEPS set, not touching apt"
    return
  fi
  local arch pkgs
  arch="$(dpkg --print-architecture)"
  pkgs=(curl unzip tar gnupg ca-certificates)

  if [[ "$arch" == "i386" ]]; then
    # Native 32-bit userland (this is what the Docker image uses).
    pkgs+=(libstdc++6 libgcc-s1)
  else
    log "Enabling i386 multi-arch (the GoldSrc binaries are 32-bit)"
    $SUDO dpkg --add-architecture i386
    pkgs+=(lib32gcc-s1 lib32stdc++6 libc6:i386)
  fi

  log "Installing packages: ${pkgs[*]}"
  $SUDO apt-get update -qq
  $SUDO apt-get install -y --no-install-recommends "${pkgs[@]}"
}

# 3. SteamCMD --------------------------------------------------------------
install_steamcmd() {
  if [[ -x "${STEAMCMD_DIR}/steamcmd.sh" ]]; then
    log "SteamCMD already installed in ${STEAMCMD_DIR}"
    return
  fi
  log "Installing SteamCMD into ${STEAMCMD_DIR}"
  mkdir -p "${STEAMCMD_DIR}"
  fetch "${WORK_DIR}/steamcmd.tar.gz" "${STEAMCMD_URL}"
  tar -xzf "${WORK_DIR}/steamcmd.tar.gz" -C "${STEAMCMD_DIR}"
}

# 4. Base game files (HLDS app 90, steam_legacy branch) ---------------------
download_game() {
  log "Downloading CS 1.6 server files via SteamCMD (branch: ${STEAM_APP_BRANCH})"
  log "This takes a while on the first run and needs several passes."

  local attempt
  for attempt in 1 2 3 4 5; do
    log "SteamCMD pass ${attempt}/5"
    # HLDS is known to need repeated app_update runs before everything lands.
    "${STEAMCMD_DIR}/steamcmd.sh" \
      +force_install_dir "${SERVER_DIR}" \
      +login anonymous \
      +app_set_config 90 mod cstrike \
      +app_update 90 -beta "${STEAM_APP_BRANCH}" validate \
      +quit > "${WORK_DIR}/steamcmd.log" 2>&1 || true

    if grep -q "Success! App '90' fully installed" "${WORK_DIR}/steamcmd.log"; then
      log "SteamCMD reports app 90 fully installed"
      return
    fi
    tail -3 "${WORK_DIR}/steamcmd.log" >&2 || true
  done

  [[ -f "${SERVER_DIR}/hlds_run" ]] || {
    cp "${WORK_DIR}/steamcmd.log" /tmp/steamcmd-failed.log 2>/dev/null || true
    die "SteamCMD never completed; log copied to /tmp/steamcmd-failed.log.
     A segfault in 'Loading Steam API' means you are on an emulated x86 host
     (e.g. an i386 container on Apple Silicon), which this stack does not
     support — run it on real x86_64 hardware."
  }
  warn "SteamCMD did not print the success line, but hlds_run exists — continuing."
}

# 4b. …or seed the game files from an existing installation ----------------
# GAME_SRC should be a Linux HLDS install (app 90). A *client* install works
# only as a source of map/model content: it has no libsteam_api.so and the
# engine refuses to start without it — see the warning at the end of this step.
copy_game_from_src() {
  log "Seeding game files from ${GAME_SRC} (SteamCMD skipped)"
  [[ -d "${GAME_SRC}/cstrike" ]] || die "GAME_SRC must contain a cstrike/ directory"

  mkdir -p "${SERVER_DIR}"
  # Everything except client-side, Windows and per-install state. Server
  # binaries copied here are replaced by the ReHLDS/ReGameDLL builds below.
  tar -cf - -C "${GAME_SRC}" \
    --exclude='./steamapps' \
    --exclude='./steamcmd' \
    --exclude='*/addons' \
    --exclude='*/cl_dlls' \
    --exclude='*/logs' \
    --exclude='*/cache' \
    --exclude='*.dll' \
    --exclude='*.dylib' \
    . | tar -xf - -C "${SERVER_DIR}"

  log "Copied $(find "${CSTRIKE_DIR}/maps" -name '*.bsp' 2>/dev/null | wc -l | tr -d ' ') maps"

  if [[ ! -f "${SERVER_DIR}/libsteam_api.so" ]]; then
    warn "libsteam_api.so is missing from ${GAME_SRC}."
    warn "It only ships with the Linux HLDS files (SteamCMD app 90) — a *client*"
    warn "install is not enough, and the engine will refuse to start without it"
    warn "('Unable to load engine, image is corrupt'). Unset GAME_SRC to let"
    warn "SteamCMD download the proper server files."
  fi
}

# 5. Signature verification ------------------------------------------------
verify_sig() {  # verify_sig <file> <sig-url>
  if [[ -n "${SKIP_GPG:-}" ]]; then
    warn "SKIP_GPG set — not verifying $(basename "$1")"
    return
  fi
  if ! gpg --list-keys "${REHLDS_GPG_KEY}" >/dev/null 2>&1; then
    log "Importing ReHLDS signing key ${REHLDS_GPG_KEY}"
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "${REHLDS_GPG_KEY}" 2>/dev/null ||
      gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "${REHLDS_GPG_KEY}" 2>/dev/null ||
      die "Could not import the ReHLDS signing key. Re-run with SKIP_GPG=1 to bypass."
  fi
  fetch "$1.asc" "$2"
  gpg --batch --verify "$1.asc" "$1" || die "Signature check FAILED for $(basename "$1")"
  log "Signature OK: $(basename "$1")"
}

backup_once() {  # backup_once <file> <suffix>
  [[ -f "$1" && ! -f "$1.$2" ]] && cp "$1" "$1.$2"
  return 0
}

# 6. ReHLDS engine ---------------------------------------------------------
install_rehlds() {
  log "Installing ReHLDS ${REHLDS_VERSION}"
  fetch "${WORK_DIR}/rehlds.zip" "${REHLDS_URL}"
  verify_sig "${WORK_DIR}/rehlds.zip" "${REHLDS_URL}.asc"
  unzip -qo "${WORK_DIR}/rehlds.zip" -d "${WORK_DIR}/rehlds"

  local bin="${WORK_DIR}/rehlds/bin/linux32"
  [[ -f "${bin}/engine_i486.so" ]] || die "engine_i486.so not found inside the ReHLDS archive"
  backup_once "${SERVER_DIR}/engine_i486.so" "orig-valve"
  cp "${bin}/engine_i486.so" "${SERVER_DIR}/engine_i486.so"

  # SteamCMD ships the rest of the engine-side files; a GAME_SRC seed does not,
  # so take them from the same ReHLDS build when they are missing.
  local f
  for f in hlds_linux core.so filesystem_stdio.so demoplayer.so; do
    [[ -f "${SERVER_DIR}/${f}" ]] || cp "${bin}/${f}" "${SERVER_DIR}/${f}"
  done
  chmod +x "${SERVER_DIR}/hlds_linux"
  [[ -f "${SERVER_DIR}/valve/dlls/director.so" ]] ||
    install -Dm755 "${bin}/valve/dlls/director.so" "${SERVER_DIR}/valve/dlls/director.so"
}

# 7. ReGameDLL_CS ----------------------------------------------------------
install_regamedll() {
  log "Installing ReGameDLL_CS ${REGAMEDLL_VERSION}"
  fetch "${WORK_DIR}/regamedll.zip" "${REGAMEDLL_URL}"
  verify_sig "${WORK_DIR}/regamedll.zip" "${REGAMEDLL_URL}.asc"
  unzip -qo "${WORK_DIR}/regamedll.zip" -d "${WORK_DIR}/regamedll"

  local src="${WORK_DIR}/regamedll/bin/linux32/cstrike"
  [[ -f "${src}/dlls/cs.so" ]] || die "cs.so not found inside the ReGameDLL archive"
  backup_once "${CSTRIKE_DIR}/dlls/cs.so" "orig-valve"
  install -Dm755 "${src}/dlls/cs.so" "${CSTRIKE_DIR}/dlls/cs.so"
  # game.cfg and delta.lst must match the game DLL; game_init.cfg is replaced
  # by ours further down (it is where bot_enable has to live).
  cp "${src}/game.cfg" "${src}/delta.lst" "${CSTRIKE_DIR}/"
}

# 8. zBot data (profiles, chatter, radio voices) ---------------------------
install_bot_profiles() {
  if [[ -f "${CSTRIKE_DIR}/BotProfile.db" && -d "${CSTRIKE_DIR}/sound/radio/bot" ]]; then
    log "zBot profiles already present"
    return
  fi
  log "Installing zBot profiles and voices"
  fetch "${WORK_DIR}/bot_profiles.zip" "${BOT_PROFILES_URL}"
  # The archive already contains a cstrike/ prefix.
  unzip -qo "${WORK_DIR}/bot_profiles.zip" -d "${SERVER_DIR}"
}

# 9. Metamod-R -------------------------------------------------------------
install_metamod() {
  log "Installing Metamod-R ${METAMOD_VERSION}"
  fetch "${WORK_DIR}/metamod.zip" "${METAMOD_URL}"
  unzip -qo "${WORK_DIR}/metamod.zip" 'addons/*' -d "${CSTRIKE_DIR}"
  rm -f "${CSTRIKE_DIR}/addons/metamod/metamod.dll"   # Windows binary, unused here

  # Metamod normally auto-detects the game DLL from liblist.gam — which we are
  # about to point at Metamod itself. Say it explicitly instead.
  local cfg="${CSTRIKE_DIR}/addons/metamod/config.ini"
  if ! grep -qE '^gamedll[[:space:]]' "$cfg" 2>/dev/null; then
    printf '\n// set by games/counter-strike/rehlds/install.sh\ngamedll dlls/cs.so\n' >> "$cfg"
  fi
}

# 10. ReUnion (lets non-Steam protocol 47/48 clients in) -------------------
install_reunion() {
  log "Installing ReUnion ${REUNION_VERSION}"
  fetch "${WORK_DIR}/reunion.zip" "${REUNION_URL}"
  unzip -qo "${WORK_DIR}/reunion.zip" -d "${WORK_DIR}/reunion"
  install -Dm755 "${WORK_DIR}/reunion/bin/Linux/reunion_mm_i386.so" \
    "${CSTRIKE_DIR}/addons/reunion/reunion_mm_i386.so"

  local cfg="${CSTRIKE_DIR}/reunion.cfg"
  local salt=""
  if [[ -f "$cfg" ]]; then
    # Keep the salt from a previous install: changing it rewrites every SteamID.
    salt="$(sed -nE 's/^[[:space:]]*SteamIdHashSalt[[:space:]]*=[[:space:]]*(.+)$/\1/p' "$cfg" | tail -1)"
  fi
  cp "${WORK_DIR}/reunion/reunion.cfg" "$cfg"

  if [[ -n "${NO_SECRETS:-}" ]]; then
    # Building a redistributable image: ship a placeholder so every deployment
    # gets its own salt at run time instead of sharing one baked into the image.
    salt="__STEAMID_HASH_SALT__"
    log "NO_SECRETS set — ReUnion salt left as a placeholder"
  elif [[ -z "$salt" || "$salt" == "__STEAMID_HASH_SALT__" ]]; then
    salt="$(head -c 48 /dev/urandom | base64 | tr -d '/+=' | head -c 40)"
    log "Generated a new ReUnion SteamIdHashSalt"
  else
    log "Kept the existing ReUnion SteamIdHashSalt"
  fi

  # Defaults reject non-Steam clients (cid_* = 5). 3 = give them a STEAM_ id
  # derived from their IP, which is what lets the Xash3D client connect.
  sed -i -E \
    -e "s|^[[:space:]]*cid_NoSteam48[[:space:]]*=.*|cid_NoSteam48 = 3|" \
    -e "s|^[[:space:]]*cid_NoSteam47[[:space:]]*=.*|cid_NoSteam47 = 3|" \
    -e "s|^[[:space:]]*SteamIdHashSalt[[:space:]]*=.*|SteamIdHashSalt = ${salt}|" \
    "$cfg"
  grep -qE '^SteamIdHashSalt' "$cfg" || printf 'SteamIdHashSalt = %s\n' "$salt" >> "$cfg"
}

# 10b. ReAPI (AMXX module exposing the ReHLDS/ReGameDLL API to plugins) ----
# Must run after AMX Mod X: it installs into addons/amxmodx/.
install_reapi() {
  log "Installing ReAPI ${REAPI_VERSION}"
  fetch "${WORK_DIR}/reapi.zip" "${REAPI_URL}"
  unzip -qo "${WORK_DIR}/reapi.zip" 'addons/*' -d "${CSTRIKE_DIR}"
  rm -f "${CSTRIKE_DIR}/addons/amxmodx/modules/reapi_amxx.dll"   # Windows build

  # AMXX only loads modules listed in modules.ini.
  local mods="${CSTRIKE_DIR}/addons/amxmodx/configs/modules.ini"
  if [[ -f "$mods" ]] && ! grep -qE '^[[:space:]]*reapi[[:space:]]*$' "$mods"; then
    printf '\n; enabled by games/counter-strike/rehlds/install.sh\nreapi\n' >> "$mods"
  fi
}

# 11b. Custom AMXX plugins from this repo ----------------------------------
install_plugins() {
  local src="${SCRIPT_DIR}/plugins"
  local dst="${CSTRIKE_DIR}/addons/amxmodx/plugins"
  local list="${CSTRIKE_DIR}/addons/amxmodx/configs/plugins.ini"

  local found=()
  local f
  while IFS= read -r -d '' f; do found+=("$f"); done \
    < <(find "$src" -maxdepth 1 -name '*.amxx' -print0 2>/dev/null)

  if [[ ${#found[@]} -eq 0 ]]; then
    log "No custom plugins in ${src} (drop .amxx files there to install them)"
    return
  fi

  log "Installing ${#found[@]} custom plugin(s) from ${src}"
  mkdir -p "$dst"
  local name
  for f in "${found[@]}"; do
    name="$(basename "$f")"
    cp "$f" "${dst}/${name}"
    if [[ -f "$list" ]] && ! grep -qE "^[[:space:]]*${name}[[:space:]]*$" "$list"; then
      printf '%s\n' "$name" >> "$list"
    fi
  done
}

# 11. AMX Mod X ------------------------------------------------------------
install_amxx() {
  log "Installing AMX Mod X ${AMXX_VERSION} (base + cstrike)"
  fetch "${WORK_DIR}/amxx-base.tar.gz" "${AMXX_BASE_URL}"
  fetch "${WORK_DIR}/amxx-cstrike.tar.gz" "${AMXX_CSTRIKE_URL}"
  tar -xzf "${WORK_DIR}/amxx-base.tar.gz" -C "${CSTRIKE_DIR}"
  tar -xzf "${WORK_DIR}/amxx-cstrike.tar.gz" -C "${CSTRIKE_DIR}"
}

# 12. Wire Metamod into the mod --------------------------------------------
patch_liblist() {
  local gam="${CSTRIKE_DIR}/liblist.gam"
  [[ -f "$gam" ]] || die "liblist.gam missing — the SteamCMD download is incomplete"

  if grep -q 'gamedll_linux "addons/metamod/metamod_i386.so"' "$gam"; then
    log "liblist.gam already points at Metamod"
    return
  fi
  log "Pointing liblist.gam gamedll_linux at Metamod"
  backup_once "$gam" "orig"
  sed -i -E 's|^gamedll_linux[[:space:]]+".*"|gamedll_linux "addons/metamod/metamod_i386.so"|' "$gam"
  grep -q 'gamedll_linux "addons/metamod/metamod_i386.so"' "$gam" ||
    printf 'gamedll_linux "addons/metamod/metamod_i386.so"\n' >> "$gam"
}

# 13. Configs --------------------------------------------------------------
install_configs() {
  log "Installing configs from ${SCRIPT_DIR}/cfg"

  local rcon=""
  if [[ -f "${CSTRIKE_DIR}/server.cfg" ]]; then
    # Tolerate the trailing comment the template carries on that line.
    rcon="$(sed -nE 's/^rcon_password[[:space:]]+"([^"]+)".*/\1/p' "${CSTRIKE_DIR}/server.cfg" | tail -1)"
  fi
  if [[ -n "${NO_SECRETS:-}" ]]; then
    rcon="__RCON_PASSWORD__"   # filled in at run time, see docker/entrypoint.sh
    log "NO_SECRETS set — rcon password left as a placeholder"
  elif [[ -z "$rcon" || "$rcon" == "__RCON_PASSWORD__" ]]; then
    rcon="$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 20)"
    log "Generated a new rcon password"
  else
    log "Kept the existing rcon password"
  fi

  install -Dm644 "${SCRIPT_DIR}/cfg/server.cfg"    "${CSTRIKE_DIR}/server.cfg"
  install -Dm644 "${SCRIPT_DIR}/cfg/bots.cfg"      "${CSTRIKE_DIR}/bots.cfg"
  install -Dm644 "${SCRIPT_DIR}/cfg/game_init.cfg" "${CSTRIKE_DIR}/game_init.cfg"
  install -Dm644 "${SCRIPT_DIR}/cfg/mapcycle.txt"  "${CSTRIKE_DIR}/mapcycle.txt"
  install -Dm644 "${SCRIPT_DIR}/cfg/plugins.ini"   "${CSTRIKE_DIR}/addons/metamod/plugins.ini"

  [[ -n "${NO_SECRETS:-}" ]] || sed -i "s|__RCON_PASSWORD__|${rcon}|" "${CSTRIKE_DIR}/server.cfg"
  RCON_PASSWORD="$rcon"
}

# 14. zBot needs navigation meshes -----------------------------------------
check_nav() {
  local navs
  navs="$(find "${CSTRIKE_DIR}/maps" -name '*.nav' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$navs" -gt 0 ]]; then
    log "Navigation meshes found: ${navs} .nav files"
    return
  fi
  if [[ -n "${NAV_SRC:-}" && -d "${NAV_SRC}" ]]; then
    log "Copying .nav files from ${NAV_SRC}"
    cp "${NAV_SRC}"/*.nav "${CSTRIKE_DIR}/maps/" 2>/dev/null || true
    return
  fi
  warn "No .nav files in cstrike/maps — zBot will generate one on first use of"
  warn "each map (slow). Copy them from a client install, e.g. on the Mac:"
  warn "  scp ~/Games/cs16/cstrike/maps/*.nav <server>:${CSTRIKE_DIR}/maps/"
}

main() {
  install_deps
  if [[ -n "${GAME_SRC:-}" ]]; then
    copy_game_from_src
  else
    install_steamcmd
    download_game
  fi
  install_rehlds
  install_regamedll
  install_bot_profiles
  install_metamod
  install_reunion
  install_amxx
  install_reapi
  install_plugins
  patch_liblist
  install_configs
  check_nav

  log "Done. Server installed in ${SERVER_DIR}"
  log "rcon password: ${RCON_PASSWORD}"
  echo
  echo "Start it with:"
  echo "  ${SCRIPT_DIR}/start.sh"
  echo "Or install the service (as root):"
  echo "  cp ${SCRIPT_DIR}/systemd/cs16-rehlds.service /etc/systemd/system/"
  echo "  systemctl enable --now cs16-rehlds"
}

main "$@"
