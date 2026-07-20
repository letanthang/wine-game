#!/bin/zsh
# Create a new 64-bit Wine prefix for a game under ~/wine-prefixes/<game-slug>.
#
# Usage:
#   scripts/new-prefix.sh <game-slug> [--fonts]
#
#   --fonts   also install corefonts + cjkfonts via winetricks
#             (needed for games with Japanese/CJK text; takes a few minutes)
#
# Safe to re-run: wineboot on an existing prefix just updates it.

set -euo pipefail

WINE_BIN="/Applications/Wine Stable.app/Contents/Resources/wine/bin"
PREFIX_ROOT="${HOME}/wine-prefixes"

log() { print -P "%F{green}==>%f $1"; }
die() { print -P "%F{red}error:%f $1" >&2; exit 1; }

[[ $# -ge 1 ]] || die "usage: $0 <game-slug> [--fonts]"
slug="$1"
[[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "slug must be lowercase kebab-case (e.g. counter-strike)"

install_fonts=false
[[ "${2:-}" == "--fonts" ]] && install_fonts=true

# Ensure wine is reachable even if ~/.zshrc PATH entry is not loaded
command -v wine >/dev/null 2>&1 || export PATH="${WINE_BIN}:${PATH}"
command -v wine >/dev/null 2>&1 || die "wine not found — run 'make install' first"

prefix="${PREFIX_ROOT}/${slug}"
mkdir -p "$prefix"

log "Initializing 64-bit prefix at ${prefix} ..."
WINEPREFIX="$prefix" WINEARCH=win64 wineboot

if $install_fonts; then
  command -v winetricks >/dev/null 2>&1 || die "winetricks not found — run 'make install' first"
  log "Installing corefonts + cjkfonts (this takes a few minutes)..."
  WINEPREFIX="$prefix" winetricks -q corefonts cjkfonts
fi

log "Done. Useful commands:"
print "  WINEPREFIX=${prefix} winecfg                  # configure"
print "  WINEPREFIX=${prefix} wine /path/to/setup.exe  # install a game"
