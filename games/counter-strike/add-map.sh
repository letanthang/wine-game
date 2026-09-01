#!/bin/zsh
# Add a custom map to the Counter-Strike 1.6 asset source and to the builds made
# from it.
#
# Maps are installed into ~/Games/assets first, not straight into a build:
# assets/ is what mac/build.sh and windows/build.sh copy from, so a map added
# there survives `make counter-strike-mac ARGS=--force`, while one dropped into
# ~/Games/cs16-mac alone is deleted by the next rebuild. Existing builds are
# then topped up from the same files.
#
# Only files the install does not already have are copied, and both cstrike/ and
# valve/ are checked before deciding: the engine adds valve/ to the search path
# (FS_AddGameHierarchy), so a map's halflife.wad or "city" skybox is already
# resolvable and the copy in the archive is redundant. Map archives routinely
# ship the whole base game's wads, and nothing here may overwrite those.
#
# Bots need maps/<map>.nav, which these archives do not carry — see mac/make-nav.sh.
#
# Usage:
#   ./add-map.sh cs_mansion aim_ak-colt
#   ./add-map.sh --dry-run cs_mansion
#   SRC=~/Games/assets ./add-map.sh <map>
#
# Re-running is safe: nothing already installed is touched.

set -euo pipefail

SRC_DIR="${SRC:-${HOME}/Games/assets}"
CACHE_DIR="${CACHE:-${HOME}/Games/.cache/cs16-maps}"
BASE_URL="https://en.ds-servers.com/maps/goldsrc/cstrike"

DRY_RUN=0
REFRESH=0
BUILDS=()

usage() {
  cat <<'EOF'
Usage: add-map.sh [options] <map-name>...

Options:
  --build <dir>   also install into this build; repeatable. Default: whichever
                  of ~/Games/cs16-mac and ~/Games/cs16-windows exist
  --refresh       re-download instead of using the cached archive
  --dry-run       show what would be installed and stop
  -h, --help      show this help

Environment:
  SRC=<dir>     asset source to install into (default ~/Games/assets)
  CACHE=<dir>   download cache               (default ~/Games/.cache/cs16-maps)
EOF
}

maps=()
while (( $# )); do
  case "$1" in
    --build) shift; [[ -n "${1:-}" ]] || { print -u2 "error: --build needs a path"; exit 2 }; BUILDS+=("$1") ;;
    --refresh) REFRESH=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) print -u2 "error: unknown option '$1'"; usage >&2; exit 2 ;;
    *) maps+=("$1") ;;
  esac
  shift
done

# -r as well as -P: the messages carry file names and map metadata, and without
# it `print` would eat the backslashes in a Windows-style path (\valve became a
# vertical tab in an earlier version of this script).
info() { print -P -r "%F{cyan}==>%f $*"; }
warn() { print -P -r "%F{yellow}warning:%f $*" >&2; }
die()  { print -P -r "%F{red}error:%f $*" >&2; exit 1; }

(( ${#maps} )) || { usage >&2; exit 2 }

for tool in curl unzip python3; do
  (( $+commands[$tool] )) || die "'$tool' not found"
done

[[ -d "$SRC_DIR/cstrike" ]] || die "no cstrike/ in ${SRC_DIR} — set SRC=<dir> to the asset source"
SRC_DIR="${SRC_DIR:A}"

# Default to whatever builds are on this machine, so one run keeps the asset
# source and the playable installs in step.
if (( ${#BUILDS} == 0 )); then
  for candidate in "${HOME}/Games/cs16-mac" "${HOME}/Games/cs16-windows"; do
    [[ -d "$candidate/cstrike" ]] && BUILDS+=("$candidate")
  done
fi

mkdir -p "$CACHE_DIR"

# A GoldSrc map is BSP version 30; the entity lump holds the wads it wants and
# the spawn points it has. A download that is really an HTML error page, or a
# BSP for another engine, is caught here rather than in the game.
inspect_bsp() {
  python3 - "$1" <<'PY'
import re, struct, sys

path = sys.argv[1]
with open(path, 'rb') as fh:
    data = fh.read()

if len(data) < 8:
    sys.exit("too small to be a BSP")
version = struct.unpack_from('<i', data, 0)[0]
if version != 30:
    sys.exit(f"BSP version {version}, expected 30 (GoldSrc)")

offset, length = struct.unpack_from('<ii', data, 4)
entities = data[offset:offset + length].split(b'\x00')[0].decode('latin-1')
worldspawn = entities.split('}')[0]


def key(name):
    match = re.search(r'"%s"\s+"([^"]*)"' % name, worldspawn)
    return match.group(1) if match else ''


spawns = entities.count('info_player_deathmatch') + entities.count('info_player_start')
if spawns == 0:
    sys.exit("no player spawn points — the map would drop everyone into spectator")

# Consumed by the caller as shell-readable lines.
print(f"title={key('message')}")
print(f"sky={key('skyname')}")
print(f"spawns={spawns}")
print(f"hostages={entities.count('hostage_entity')}")
# Only the file names matter; the paths are from the mapper's own machine.
wads = [w.replace('\\', '/').split('/')[-1] for w in key('wad').split(';') if w.strip()]
print(f"wads={' '.join(wads)}")
PY
}

# Where the engine can already find a file: the mod first, then valve/.
have_file() {
  local rel="$1" root
  for root in "${SRC_DIR}/cstrike" "${SRC_DIR}/valve"; do
    [[ -f "${root}/${rel}" ]] && return 0
  done
  return 1
}

for map in $maps; do
  print ""
  info "=== ${map}"

  archive="${CACHE_DIR}/${map}.zip"
  if [[ -s "$archive" ]] && (( ! REFRESH )); then
    info "Using cached ${archive:t}"
  else
    info "Downloading ${BASE_URL}/${map}.zip"
    curl -fL --progress-bar --max-time 300 -o "${archive}.part" "${BASE_URL}/${map}.zip" \
      || die "download failed — check the map name, or fetch the archive by hand into ${CACHE_DIR}"
    mv "${archive}.part" "$archive"
  fi

  tmp="$(mktemp -d)"
  {
    unzip -qo "$archive" -d "$tmp" || die "${archive:t} is not a readable zip"

    bsp="${tmp}/maps/${map}.bsp"
    [[ -f "$bsp" ]] || die "the archive has no maps/${map}.bsp"

    typeset -A meta
    for line in ${(f)"$(inspect_bsp "$bsp")"}; do
      meta[${line%%=*}]="${line#*=}"
    done

    info "BSP ok: ${meta[spawns]} spawn points, ${meta[hostages]} hostages${meta[sky]:+, sky \"${meta[sky]}\"}"

    # Textures live in wads, and a missing one leaves the map checkerboarded.
    missing_wads=()
    for wad in ${=meta[wads]}; do
      have_file "$wad" || [[ -f "${tmp}/${wad}" ]] || missing_wads+=("$wad")
    done
    (( ${#missing_wads} )) && warn "wads neither installed nor in the archive: ${missing_wads}"

    # Decide file by file, so the base game's own wads and models are never
    # replaced by a map author's copy of them.
    new_files=()
    skipped=0
    for file in "${tmp}"/**/*(.N); do
      rel="${file#${tmp}/}"
      if have_file "$rel"; then
        skipped=$(( skipped + 1 ))
      else
        new_files+=("$rel")
      fi
    done

    if (( ${#new_files} == 0 )); then
      info "Everything in the archive is already installed — nothing to do"
      continue
    fi

    info "Installing ${#new_files} file(s), skipping ${skipped} already present:"
    for rel in $new_files; do
      print "      ${rel} ($(du -h "${tmp}/${rel}" | cut -f1 | tr -d ' '))"
    done

    if (( DRY_RUN )); then
      info "--dry-run: stopping here"
      continue
    fi

    for rel in $new_files; do
      mkdir -p "${SRC_DIR}/cstrike/${rel:h}"
      cp "${tmp}/${rel}" "${SRC_DIR}/cstrike/${rel}"
    done
    info "Added to ${SRC_DIR}/cstrike"

    # maps.lst is what the map list in the menu reads; without an entry the map
    # is only reachable by `map <name>` from the console.
    lst="${SRC_DIR}/cstrike/maps.lst"
    if [[ -f "$lst" ]] && ! grep -qE "^${map}( |\$)" "$lst"; then
      print -- "${map} \"${meta[title]:-No Title}\"" >> "$lst"
      info "Listed in maps.lst as \"${meta[title]:-No Title}\""
    fi

    for build in $BUILDS; do
      for rel in $new_files; do
        [[ -f "${build}/cstrike/${rel}" ]] && continue
        mkdir -p "${build}/cstrike/${rel:h}"
        cp "${tmp}/${rel}" "${build}/cstrike/${rel}"
      done
      [[ -f "${build}/cstrike/maps.lst" ]] && ! grep -qE "^${map}( |\$)" "${build}/cstrike/maps.lst" && \
        print -- "${map} \"${meta[title]:-No Title}\"" >> "${build}/cstrike/maps.lst"
      info "Added to ${build}/cstrike"
    done

    [[ -f "${SRC_DIR}/cstrike/maps/${map}.nav" ]] || \
      warn "no maps/${map}.nav — the CZ bots cannot play this map until one is generated (mac/make-nav.sh ${map})"
  } always {
    rm -rf "$tmp"
  }
done

print ""
info "Done"
