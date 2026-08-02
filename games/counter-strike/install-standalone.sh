#!/bin/zsh
# Turn ~/Games/cs16 into a standalone CS 1.6 install: a play.sh launcher, a
# double-clickable .app, bot settings and a player-facing README, none of which
# reference this repo at runtime. The game folder can then be renamed, moved or
# copied to another Mac and still work, and this repo can be deleted.
#
# What gets installed:
#   <game>/play.sh                   the launcher (from play.sh here)
#   <game>/README.txt                player notes (from game-readme.txt here)
#   <game>/cstrike/bots.cfg          bot settings, only if not there already
#   <game>/Counter-Strike 1.6.app    thin wrapper around play.sh
#
# Re-running is safe: it refreshes the launcher, the README and the app, and
# leaves cstrike/bots.cfg alone unless --reset-bots is passed.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

GAME_DIR="${GAME_DIR:-${HOME}/Games/cs16}"
OFFLINE_MAP=""
RESET_BOTS=0

usage() {
  cat <<'EOF'
Usage: install-standalone.sh [options]

Options:
  --offline [map]  build the app so it jumps straight into a match against bots
                   on <map> (default de_dust2) instead of opening the menu; it
                   gets its own name and can live next to the normal one
  --reset-bots     overwrite <game>/cstrike/bots.cfg with this repo's template,
                   discarding local edits
  -h, --help       show this help

Environment:
  GAME_DIR=<dir>   game install    (default ~/Games/cs16)
  APP=<path>       bundle to write (default <GAME_DIR>/Counter-Strike 1.6.app)
EOF
}

while (( $# )); do
  case "$1" in
    --offline)
      OFFLINE_MAP="de_dust2"
      # An optional map name may follow, but not another flag.
      if [[ -n "${2:-}" && "$2" != -* ]]; then
        OFFLINE_MAP="$2"
        shift
      fi
      ;;
    --reset-bots) RESET_BOTS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "error: unknown option '$1'"; usage >&2; exit 2 ;;
  esac
  shift
done

info() { print -P "%F{cyan}==>%f $*"; }
warn() { print -P "%F{yellow}warning:%f $*" >&2; }
die()  { print -P "%F{red}error:%f $*" >&2; exit 1; }

[[ -d "$GAME_DIR" ]] || die "no such directory: ${GAME_DIR}"
GAME_DIR="${GAME_DIR:A}"
CSTRIKE_DIR="${GAME_DIR}/cstrike"

[[ -x "${GAME_DIR}/xash3d" ]] || die "xash3d engine not found in ${GAME_DIR} — see README.md (Setup)"

for f in play.sh app-launcher.sh game-readme.txt bots.cfg; do
  [[ -f "${SCRIPT_DIR}/${f}" ]] || die "${f} is missing next to this script"
done

# --- launcher and notes ------------------------------------------------------

info "Installing play.sh and README.txt into ${GAME_DIR}"
install -m 755 "${SCRIPT_DIR}/play.sh" "${GAME_DIR}/play.sh"
install -m 644 "${SCRIPT_DIR}/game-readme.txt" "${GAME_DIR}/README.txt"

# --- bot settings ------------------------------------------------------------

# The installed copy is the source of truth from here on, so a re-run must not
# clobber hand edits. Only --reset-bots goes back to the repo template.
if [[ ! -f "${CSTRIKE_DIR}/bots.cfg" ]]; then
  info "Installing cstrike/bots.cfg"
  install -m 644 "${SCRIPT_DIR}/bots.cfg" "${CSTRIKE_DIR}/bots.cfg"
elif (( RESET_BOTS )); then
  info "Resetting cstrike/bots.cfg to the repo template"
  install -m 644 "${SCRIPT_DIR}/bots.cfg" "${CSTRIKE_DIR}/bots.cfg"
else
  info "Keeping the existing cstrike/bots.cfg (--reset-bots overwrites it)"
fi

# Only listen servers get the bots: on -dedicated the game DLL never registers
# the bot commands, so server.cfg exec'ing bots.cfg would print a screen of
# "Unknown command" warnings instead (verified 2026-07-31, see README.md).
LISTENSERVER="${CSTRIKE_DIR}/listenserver.cfg"
if [[ -f "$LISTENSERVER" ]] && ! grep -q '^exec bots.cfg' "$LISTENSERVER"; then
  info "Making listenserver.cfg exec bots.cfg"
  [[ -f "${LISTENSERVER}.orig-no-bots" ]] || cp "$LISTENSERVER" "${LISTENSERVER}.orig-no-bots"
  print "\n// bot settings (installed by install-standalone.sh)\nexec bots.cfg" >> "$LISTENSERVER"
fi

# Drop the exec line older versions of the launcher appended to server.cfg.
SERVER_CFG="${CSTRIKE_DIR}/server.cfg"
if [[ -f "$SERVER_CFG" ]] && grep -q '^exec bots.cfg' "$SERVER_CFG"; then
  info "Removing the stale exec line from server.cfg"
  sed -i '' \
    -e '\|^// bot settings (installed by games/counter-strike/run.sh)$|d' \
    -e '\|^// bot settings (installed by install-standalone.sh)$|d' \
    -e '/^exec bots.cfg$/d' \
    "$SERVER_CFG"
fi

# --- app bundle --------------------------------------------------------------

# The offline variant gets its own name so it can live next to the normal app
# instead of replacing it. An explicit APP= always wins.
if [[ -n "${APP:-}" ]]; then
  APP_PATH="$APP"
elif [[ -n "$OFFLINE_MAP" ]]; then
  APP_PATH="${GAME_DIR}/Counter-Strike 1.6 (Bots).app"
else
  APP_PATH="${GAME_DIR}/Counter-Strike 1.6.app"
fi

# Bundle name = folder name without .app. Two variants must not share a bundle
# identifier, or Finder and the Dock treat them as the same application.
BUNDLE_NAME="${${APP_PATH:t}:r}"
BUNDLE_ID_SUFFIX=""
[[ -n "$OFFLINE_MAP" ]] && BUNDLE_ID_SUFFIX=".offline"

info "Building ${APP_PATH}"
rm -rf "$APP_PATH"
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"

install -m 755 "${SCRIPT_DIR}/app-launcher.sh" "${APP_PATH}/Contents/MacOS/counter-strike"

# Only used if the app is moved out of the game folder; normally the launcher
# works out the game dir from its own location.
print -- "$GAME_DIR" > "${APP_PATH}/Contents/Resources/game-dir"

[[ -n "$OFFLINE_MAP" ]] && print -- "+map ${OFFLINE_MAP}" > "${APP_PATH}/Contents/Resources/launch-args"

# --- icon --------------------------------------------------------------------

# cstrike/game.ico is only 32x32, so the large sizes are upscaled and look soft.
# It is still better than the generic application icon; skip it if anything in
# the conversion chain fails.
make_icon() {
  local ico="${CSTRIKE_DIR}/game.ico"
  [[ -f "$ico" ]] || return 1

  local tmp
  tmp="$(mktemp -d)"

  # zsh has no RETURN trap; `always` is what runs the cleanup on every exit path
  # out of the block, including the early `return 1`s.
  {
    sips -s format png "$ico" --out "${tmp}/base.png" >/dev/null 2>&1 || return 1

    local iconset="${tmp}/cs16.iconset"
    mkdir -p "$iconset"
    local -A sizes=(
      icon_16x16       16
      icon_16x16@2x    32
      icon_32x32       32
      icon_32x32@2x    64
      icon_128x128    128
      icon_128x128@2x 256
      icon_256x256    256
      icon_256x256@2x 512
      icon_512x512    512
    )
    local name
    for name in ${(k)sizes}; do
      sips -z ${sizes[$name]} ${sizes[$name]} "${tmp}/base.png" \
        --out "${iconset}/${name}.png" >/dev/null 2>&1 || return 1
    done

    iconutil -c icns "$iconset" -o "${APP_PATH}/Contents/Resources/cs16.icns" >/dev/null 2>&1
  } always {
    rm -rf "$tmp"
  }
}

if make_icon; then
  info "Icon built from cstrike/game.ico"
  ICON_KEY='  <key>CFBundleIconFile</key>
  <string>cs16</string>'
else
  warn "could not build an icon — the app gets the generic one"
  ICON_KEY=''
fi

# --- Info.plist --------------------------------------------------------------

# LSMinimumSystemVersion follows the *engine* (14.0). The CS16Client dylibs in a
# stock install need macOS 26.0, but a locally rebuilt client can be lower, so
# the bundle does not hard-block those — see README.md (Requirements).
cat > "${APP_PATH}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${BUNDLE_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${BUNDLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>local.xash3d.cs16${BUNDLE_ID_SUFFIX}</string>
  <key>CFBundleExecutable</key>
  <string>counter-strike</string>
${ICON_KEY}
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.6</string>
  <key>CFBundleVersion</key>
  <string>1.6</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.action-games</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

plutil -lint "${APP_PATH}/Contents/Info.plist" >/dev/null || die "generated Info.plist is malformed"

# Finder caches bundle metadata by mtime; touching the bundle makes it pick up
# the new icon straight away instead of after a relaunch.
touch "$APP_PATH"

info "Done: ${GAME_DIR} is now standalone"
if [[ -n "$OFFLINE_MAP" ]]; then
  print "Double-click ${APP_PATH:t} to drop straight into ${OFFLINE_MAP} against bots."
else
  print "Double-click ${APP_PATH:t} to play. Drag it to the Dock to keep it one click away."
fi
print "The folder no longer needs this repo — see ${GAME_DIR}/README.txt."
print "Launch output goes to ~/Library/Logs/counter-strike-16.log"
