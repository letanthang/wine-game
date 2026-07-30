#!/usr/bin/env bash
# STEP 1 of two — prepare the complete CS 1.6 server file tree on this host.
#
#   fetch.sh  →  local/server-files/  →  docker/Dockerfile (step 2) → image
#
# Downloads and assembles everything the server needs: HLDS game files (SteamCMD,
# app 90, steam_legacy branch), ReHLDS, ReGameDLL_CS, zBot data, Metamod-R,
# ReUnion, AMX Mod X, ReAPI, this repo's cfg/ and plugins/. Then writes
# SHA256SUMS so the tree can be checked before it is baked into an image.
#
# Runs on the host, not in a container — SteamCMD needs a real x86 CPU or Rosetta
# and segfaults under QEMU. On macOS the Homebrew cask works natively; the Linux
# files are still what gets downloaded.
#
# Usage:
#   ./fetch.sh                 # assemble local/server-files
#   OUT_DIR=/tmp/sf ./fetch.sh # somewhere else
#   SKIP_GPG=1 ./fetch.sh      # no access to keyservers
#
# Re-running is cheap: SteamCMD only fetches changed files and the release
# archives are small.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/local/server-files}"

log()  { printf '\033[32m==>\033[0m %s\n' "$1"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

command -v curl  >/dev/null 2>&1 || die "curl is required"
command -v unzip >/dev/null 2>&1 || die "unzip is required"
command -v gpg   >/dev/null 2>&1 || [[ -n "${SKIP_GPG:-}" ]] ||
  die "gpg is required to verify the ReHLDS releases (or set SKIP_GPG=1)"

log "Assembling server files in ${OUT_DIR}"
mkdir -p "${OUT_DIR}"

# install.sh does the real work. SKIP_DEPS: this host is not the server, so no
# apt. NO_SECRETS: the rcon password and ReUnion salt stay as placeholders and
# are generated per container run, so nothing secret ends up in the image.
SERVER_DIR="${OUT_DIR}" \
SKIP_DEPS=1 \
NO_SECRETS=1 \
  "${SCRIPT_DIR}/install.sh" game engine addons configs

# Checksums for the whole tree, so step 2 (or a reviewer) can verify what it is
# about to package. Paths are relative to OUT_DIR.
log "Writing SHA256SUMS"
if command -v sha256sum >/dev/null 2>&1; then
  ( cd "${OUT_DIR}" && find . -type f ! -name SHA256SUMS -print0 \
      | sort -z | xargs -0 sha256sum > SHA256SUMS )
else   # macOS
  ( cd "${OUT_DIR}" && find . -type f ! -name SHA256SUMS -print0 \
      | sort -z | xargs -0 shasum -a 256 > SHA256SUMS )
fi

files="$(wc -l < "${OUT_DIR}/SHA256SUMS" | tr -d ' ')"
size="$(du -sh "${OUT_DIR}" | cut -f1)"

echo
log "Done: ${files} files, ${size}"
echo
cat "${OUT_DIR}/BUILD_INFO"
echo
echo "Next: make build      # step 2, packages this tree into the image"
