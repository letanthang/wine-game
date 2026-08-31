#!/bin/zsh
# Clear the macOS quarantine flag from the Counter-Strike 1.6 game folder.
#
# macOS tags anything that arrives by download, AirDrop or an unpacked ZIP with
# com.apple.quarantine. The engine, the client dylibs and the .app are not
# signed by an identified developer, so Gatekeeper refuses to start them while
# that flag is set — the app "cannot be opened because it is damaged", or it
# opens and dies with no useful message.
#
# This file is installed into the game folder and is self-contained: with no
# argument it cleans the folder it sits in, so the whole folder can be copied to
# another Mac and fixed up with one command.
#
# Source: games/counter-strike/remove-quarantine.sh in the wine-game repo,
# copied here by install-standalone.sh — edit it there if you still have the
# repo.
#
# Usage:
#   ./remove-quarantine.sh              clean the folder this script is in
#   ./remove-quarantine.sh <folder>     clean another folder
#   zsh remove-quarantine.sh            if the script itself is not executable

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: remove-quarantine.sh [folder]

Removes the com.apple.quarantine flag from every file in <folder>
(default: the folder this script is in).
EOF
}

TARGET="${0:A:h}"
while (( $# )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -*) print -u2 "error: unknown option '$1'"; usage >&2; exit 2 ;;
    *) TARGET="$1" ;;
  esac
  shift
done

info() { print -P "%F{cyan}==>%f $*"; }
die()  { print -P "%F{red}error:%f $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "quarantine flags only exist on macOS"
[[ -d "$TARGET" ]] || die "no such folder: ${TARGET}"
TARGET="${TARGET:A}"

# `find -xattrname` is BSD find only, which is what macOS ships.
count_flagged() { find "$TARGET" -xattrname com.apple.quarantine 2>/dev/null | wc -l | tr -d ' ' }

before="$(count_flagged)"
if [[ "$before" == 0 ]]; then
  info "Nothing is quarantined in ${TARGET}"
  exit 0
fi

info "Clearing the quarantine flag from ${before} item(s) in ${TARGET}"
# Files owned by another user cannot be cleared; report that instead of dying
# halfway through, since the rest of the folder is still worth fixing.
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

after="$(count_flagged)"
if [[ "$after" != 0 ]]; then
  print -u2 "warning: ${after} item(s) are still quarantined — check their ownership:"
  find "$TARGET" -xattrname com.apple.quarantine 2>/dev/null | head -5 >&2
  exit 1
fi

# Finder caches an app bundle's Gatekeeper verdict by mtime, so a bundle that
# was already refused stays refused until something touches it.
for app in "$TARGET"/*.app(N); do
  touch "$app"
done

info "Done — the game can be launched now"
