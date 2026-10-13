#!/usr/bin/env bash
# Launch Counter-Strike 1.6 on the native Xash3D FWGS engine (Linux build).
#
# This file is installed into the game folder and is self-contained: it resolves
# everything from its own location, so the folder can be renamed or moved and
# still work.
#
# Source: games/counter-strike/debian/play.sh in the wine-game repo, copied here
# by debian/build.sh — edit it there if you still have the repo.
#
# Usage:
#   ./play.sh                 main menu
#   ./play.sh -windowed       any engine flag passes through
#   ./play.sh +map de_dust2   straight into a match against bots
#   BOTS=12 ./play.sh         set the bot count first (see below)
#   SKIP_LIB_CHECK=1 ./play.sh   skip the missing-library check below

set -euo pipefail

GAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSTRIKE_DIR="${GAME_DIR}/cstrike"

if [[ ! -x "${GAME_DIR}/xash3d" ]]; then
  echo "error: xash3d engine not found in ${GAME_DIR}" >&2
  echo "play.sh has to stay in the game folder, next to the engine." >&2
  exit 1
fi

# --- missing libraries -------------------------------------------------------

# The engine brings its own SDL2, so the package needs very little from the
# system — but what it does need fails quietly. Without libfreetype the menu
# library does not load, the game reports `native object "MenuFactory" is
# unavailable` and falls back to the engine's own menu. So the libraries are
# resolved up front and the apt command is printed; nothing is installed from
# here.
check_libs() {
  command -v ldd >/dev/null || return 0

  # CS16Client suffixes its libraries on 64-bit only, which is also what tells
  # the two packages apart.
  local pkg_arch="i386"
  [[ -f "${CSTRIKE_DIR}/dlls/cs_amd64.so" ]] && pkg_arch="amd64"

  local host_arch
  host_arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  [[ "$host_arch" == "x86_64" ]] && host_arch="amd64"

  # A foreign-architecture package needs the :i386 qualifier, and multiarch
  # enabled first.
  local qual="" prep=""
  if [[ "$pkg_arch" != "$host_arch" ]]; then
    qual=":${pkg_arch}"
    prep="sudo dpkg --add-architecture ${pkg_arch} && sudo apt update && "
  fi

  # ldd cannot even read a binary whose loader is not installed, which is how a
  # missing i386 libc shows up on an amd64 system.
  if ! ldd "${GAME_DIR}/xash3d" >/dev/null 2>&1; then
    echo "error: this is the ${pkg_arch} build and this system (${host_arch}) cannot run it yet." >&2
    echo "Install the ${pkg_arch} runtime, then start the game again:" >&2
    echo "  ${prep}sudo apt install libc6${qual} libstdc++6${qual} libfreetype6${qual} libgl1${qual}" >&2
    exit 1
  fi

  local missing="" f lib
  for f in "${GAME_DIR}/xash3d" "${GAME_DIR}/libxash.so" \
           "${CSTRIKE_DIR}"/cl_dlls/*.so "${CSTRIKE_DIR}"/dlls/*.so; do
    [[ -f "$f" ]] || continue
    while read -r lib; do
      [[ " $missing " == *" $lib "* ]] || missing+=" $lib"
    done < <(LD_LIBRARY_PATH="${GAME_DIR}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$f" 2>/dev/null \
               | awk '/not found/ { print $1 }')
  done

  # The renderer is opened at run time, so ldd never sees it. A dedicated
  # server does not need one.
  if [[ " $* " != *" -dedicated "* ]] && command -v ldconfig >/dev/null \
     && ! ldconfig -p | grep -q 'libGL\.so\.1'; then
    missing+=" libGL.so.1"
  fi

  [[ -n "$missing" ]] || return 0

  local pkgs=""
  for lib in $missing; do
    case "$lib" in
      libfreetype.so.6) pkgs+=" libfreetype6${qual}" ;;
      libstdc++.so.6)   pkgs+=" libstdc++6${qual}" ;;
      libgcc_s.so.1)    pkgs+=" libgcc-s1${qual}" ;;
      libGL.so.1)       pkgs+=" libgl1${qual}" ;;
      *)                pkgs+=" <package providing ${lib}>" ;;
    esac
  done

  echo "error: missing system libraries:${missing}" >&2
  echo "Install them, then start the game again:" >&2
  echo "  ${prep}sudo apt install${pkgs}" >&2
  echo "(SKIP_LIB_CHECK=1 ./play.sh starts the game anyway.)" >&2
  exit 1
}

[[ -n "${SKIP_LIB_CHECK:-}" ]] || check_libs "$@"

# --- bots --------------------------------------------------------------------

# BOTS=<n> edits cstrike/bots.cfg in place. That file is the source of truth for
# bot settings and nothing rewrites it behind your back, so the count sticks
# until it is changed again — edit the file directly for anything else.
if [[ -n "${BOTS:-}" ]]; then
  if [[ ! "$BOTS" =~ ^[0-9]+$ ]]; then
    echo "error: BOTS must be a number, got '${BOTS}'" >&2
    exit 1
  fi
  if [[ -f "${CSTRIKE_DIR}/bots.cfg" ]]; then
    sed -i -E "s/^bot_quota .*/bot_quota ${BOTS}/" "${CSTRIKE_DIR}/bots.cfg"
  else
    echo "warning: ${CSTRIKE_DIR}/bots.cfg is missing, BOTS=${BOTS} ignored" >&2
  fi
fi

cd "$GAME_DIR"
exec ./xash3d -console -game cstrike "$@"
