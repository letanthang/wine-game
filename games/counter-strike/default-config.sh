#!/bin/zsh
# Write a first-run cstrike/config.cfg holding Counter-Strike's default key
# bindings, for a freshly assembled game folder.
#
# Usage: default-config.sh <game-dir>
#
# The builds exclude config.cfg from the asset copy on purpose (it is local
# state from whoever played the source install last). Without it, the first
# start has no CS bindings at all: valve.rc's "exec default.cfg" is commented
# out and the install ships no default.cfg, so the engine falls back to its
# built-in Half-Life bindings — no buy menu on B, no team menu on M, no drop on
# G — and the player has to press "Use defaults" under Options > Controls.
#
# That button reads cstrike/gfx/shell/kb_def.lst, so this script turns the same
# file into bind commands. The engine rewrites config.cfg on exit, adding the
# archived cvars and any binding the player changes, so this is only ever the
# starting point.
#
# An existing config.cfg is never touched.

set -euo pipefail

die() { print -P "%F{red}error:%f $*" >&2; exit 1; }

(( $# == 1 )) || die "usage: ${0:t} <game-dir>"

CSTRIKE_DIR="${1}/cstrike"
KB_DEF="${CSTRIKE_DIR}/gfx/shell/kb_def.lst"
CONFIG="${CSTRIKE_DIR}/config.cfg"

[[ -f "$KB_DEF" ]] || die "no ${KB_DEF} — is ${1} a CS 1.6 game folder?"

if [[ -e "$CONFIG" ]]; then
  print "Keeping the existing ${CONFIG}"
  exit 0
fi

# kb_def.lst lines look like:  "b"<tabs>"buy"  with CRLF endings.
#
# Two keys need translating to what the engine itself writes into config.cfg:
#   ;   is a command separator, so the engine names the key "SEMICOLON"
#   \\  the second +attack2 key; the engine resolves no key from this name and
#       a config it saved after "Use defaults" has no such binding either, so
#       it is left out rather than written in a form nothing reads back
{
  print "// Default Counter-Strike key bindings, generated from gfx/shell/kb_def.lst"
  print "// by games/counter-strike/default-config.sh (wine-game repo)."
  print "// The engine rewrites this file on exit; edit bindings in the game instead."
  print "unbindall"
  tr -d '\r' < "$KB_DEF" | awk -F'"' '
    NF >= 4 && $2 != "" {
      key = $2; cmd = $4
      if (key == "\\\\") next
      if (key == ";") key = "SEMICOLON"
      printf "bind \"%s\" \"%s\"\n", key, cmd
    }'
} > "$CONFIG"

print "Wrote $(grep -c '^bind ' "$CONFIG") default key bindings to ${CONFIG}"
