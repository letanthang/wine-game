#!/bin/zsh
# Copy every non-system library a cs16-mac build links against into the build
# itself, so the folder really is self-contained.
#
# CS16Client's released menu library is linked against Homebrew's freetype:
#
#   cstrike/cl_dlls/menu_arm64.dylib -> /opt/homebrew/opt/freetype/lib/libfreetype.6.dylib
#                                    -> /opt/homebrew/opt/libpng/lib/libpng16.16.dylib
#
# That path exists on the machine the build is assembled on (Homebrew is
# installed for winetricks) and on no machine that just receives the folder.
# dlopen then fails, gameui.hInstance is never set, and the game reports
# `native object "MenuFactory" is unavailable` while the engine quietly falls
# back to its own menu — which is why Training and Load game are greyed out.
# The client and server libraries have no such dependency, so the game still
# starts and a map still loads; only the CS16Client UI is missing.
#
# This walks the dependency graph, copies each outside library next to the
# binary that needs it, rewrites the reference to @loader_path, and re-signs:
# arm64 will not load a Mach-O whose signature no longer matches its load
# commands, and install_name_tool invalidates the ad-hoc one the linker left.
#
# Libraries under /usr/lib and /System are left alone — they ship with macOS.
#
# Usage:
#   ./vendor-dylibs.sh                 the build at ~/Games/cs16-mac
#   ./vendor-dylibs.sh <game-dir>      another build
#
# Re-running is safe: an already vendored reference is a @loader_path one and is
# skipped. build.sh runs this as part of every build.

set -euo pipefail

GAME_DIR="${HOME}/Games/cs16-mac"

usage() {
  cat <<'EOF'
Usage: vendor-dylibs.sh [game-dir]

Copies every library the build links against from outside /usr/lib and /System
into the build, repoints the references at @loader_path and re-signs ad-hoc.
EOF
}

while (( $# )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -*) print -u2 "error: unknown option '$1'"; usage >&2; exit 2 ;;
    *) GAME_DIR="$1" ;;
  esac
  shift
done

info() { print -P "%F{cyan}==>%f $*"; }
warn() { print -P "%F{yellow}warning:%f $*" >&2; }
die()  { print -P "%F{red}error:%f $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Mach-O binaries only exist on macOS"

for tool in otool install_name_tool codesign; do
  (( $+commands[$tool] )) || die "'$tool' not found — install the Xcode command line tools (xcode-select --install)"
done

[[ -d "$GAME_DIR" ]] || die "no such folder: ${GAME_DIR}"
GAME_DIR="${GAME_DIR:A}"
[[ -x "${GAME_DIR}/xash3d" ]] || die "${GAME_DIR} does not look like a cs16-mac build (no xash3d)"

# Absolute dependencies of a Mach-O that macOS does not ship itself.
#
# The load commands are read directly rather than through `otool -L`, whose
# first line for a dylib is the file's own LC_ID_DYLIB — for these binaries that
# is the path on the CI machine that built them
# (/Users/runner/work/xash3d-fwgs/...), which is not a dependency and must not
# be rewritten. Fat binaries list their commands once per architecture, hence
# the dedupe.
#
# `|| true` because most files handed to this are not Mach-O at all and otool
# fails on them, which `pipefail` would otherwise turn into a silent exit.
external_deps() {
  { otool -l "$1" 2>/dev/null || true; } \
    | awk '
        $1 == "cmd"  { cmd = $2 }
        $1 == "name" && cmd ~ /^LC_(LOAD|LOAD_WEAK|REEXPORT|LOAD_UPWARD)_DYLIB$/ { print $2 }
      ' \
    | sort -u \
    | grep -E '^/' \
    | grep -vE '^(/usr/lib|/System)/' || true
}

# Binaries still to inspect; vendored copies are appended as they are made, so
# a dependency of a dependency (libpng behind freetype) is picked up too.
queue=()
for f in "${GAME_DIR}"/**/*(.N); do
  [[ "$f" == *.dylib || -x "$f" ]] || continue
  queue+=("$f")
done

vendored=0
rewritten=0
# Paths of the copies made below: their id was rewritten at copy time, so they
# need a fresh signature even when they have no dependencies of their own.
typeset -A is_vendored

while (( ${#queue} )); do
  target="${queue[1]}"
  queue=("${queue[@]:1}")

  deps=("${(@f)$(external_deps "$target")}")
  changed=0

  for dep in $deps; do
    [[ -n "$dep" ]] || continue
    # An absolute path that already points inside the build travels with it.
    [[ "$dep" == "${GAME_DIR}"/* ]] && continue
    name="${dep:t}"
    # Next to the binary that needs it, so @loader_path resolves without an
    # rpath and keeps working wherever the game folder is moved.
    copy="${target:h}/${name}"

    if [[ ! -f "$copy" ]]; then
      [[ -f "$dep" ]] || die "${target:t} needs ${dep}, which is not on this machine either"
      info "Vendoring ${name} into ${${target:h}#${GAME_DIR}/}/"
      cp "$dep" "$copy"
      chmod u+w "$copy"
      # Its own id still points at the Homebrew prefix; anything linking against
      # the copy later would record that path again.
      install_name_tool -id "@loader_path/${name}" "$copy"
      queue+=("$copy")
      is_vendored[$copy]=1
      vendored=$(( vendored + 1 ))
    fi

    install_name_tool -change "$dep" "@loader_path/${name}" "$target"
    changed=1
  done

  if (( changed )); then
    info "Repointed ${target#${GAME_DIR}/}"
    rewritten=$(( rewritten + 1 ))
  fi

  if (( changed )) || [[ -n "${is_vendored[$target]:-}" ]]; then
    codesign -f -s - "$target" 2>/dev/null || die "could not re-sign ${target}"
    codesign -v "$target" 2>/dev/null || die "signature still invalid after re-signing ${target}"
  fi
done

if (( vendored == 0 && rewritten == 0 )); then
  info "Nothing to vendor — the build already links only against macOS libraries"
else
  info "Vendored ${vendored} librar(y/ies), repointed ${rewritten} binary/binaries"
fi

# Static proof for the whole build, not just the files touched above.
leftover=0
for f in "${GAME_DIR}"/**/*(.N); do
  [[ "$f" == *.dylib || -x "$f" ]] || continue
  deps="$(external_deps "$f")"
  if [[ -n "$deps" ]]; then
    warn "${f#${GAME_DIR}/} still links outside the build:"
    print -- "$deps" | sed 's/^/    /' >&2
    leftover=1
  fi
done
(( leftover )) && die "the build is not self-contained"

info "Every binary links only against the build itself and macOS"
