#!/bin/zsh
# One-shot installer for the hybrid Wine setup on macOS (Apple Silicon).
# - Wine Stable.app from the Gcenx GitHub builds -> /Applications
# - winetricks + cabextract via Homebrew
# - PATH entry appended to ~/.zshrc
# Safe to re-run: every step is skipped if already done.

set -euo pipefail

WINE_VERSION="11.0_1"
WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/${WINE_VERSION}/wine-stable-${WINE_VERSION}-osx64.tar.xz"
WINE_APP="/Applications/Wine Stable.app"
WINE_BIN="${WINE_APP}/Contents/Resources/wine/bin"
ZSHRC="${HOME}/.zshrc"
PATH_LINE='export PATH="/Applications/Wine Stable.app/Contents/Resources/wine/bin:$PATH"'

log()  { print -P "%F{green}==>%f $1"; }
warn() { print -P "%F{yellow}==>%f $1"; }

# 1. Rosetta 2 -----------------------------------------------------------
if arch -x86_64 /usr/bin/true 2>/dev/null; then
  log "Rosetta 2: OK"
else
  log "Installing Rosetta 2 (may prompt for confirmation)..."
  softwareupdate --install-rosetta --agree-to-license
fi

# 2. Wine Stable.app (Gcenx build) ---------------------------------------
if [[ -d "$WINE_APP" ]]; then
  log "Wine Stable.app already installed, skipping download"
else
  log "Downloading Wine Stable ${WINE_VERSION} (~250 MB)..."
  tmpfile="$(mktemp -t wine-stable).tar.xz"
  curl -L --progress-bar -o "$tmpfile" "$WINE_URL"
  log "Extracting into /Applications..."
  tar -xJf "$tmpfile" -C /Applications
  rm -f "$tmpfile"
fi

# 3. winetricks + cabextract (Homebrew) ----------------------------------
if command -v winetricks >/dev/null 2>&1; then
  log "winetricks: OK ($(command -v winetricks))"
else
  log "Installing winetricks via Homebrew..."
  brew install winetricks
fi

# 4. PATH in ~/.zshrc ------------------------------------------------------
if grep -qF "$PATH_LINE" "$ZSHRC" 2>/dev/null; then
  log "PATH entry already present in ~/.zshrc"
else
  log "Appending Wine PATH entry to ~/.zshrc"
  printf '\n# Wine (Gcenx build) CLI tools\n%s\n' "$PATH_LINE" >> "$ZSHRC"
fi

# 5. Verify ----------------------------------------------------------------
export PATH="${WINE_BIN}:${PATH}"
log "wine version: $(wine --version)"
log "Done. Open a new terminal (or 'source ~/.zshrc') to pick up PATH."
warn "If macOS blocks the first launch: System Settings -> Privacy & Security -> Open Anyway."
