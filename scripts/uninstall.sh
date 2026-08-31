#!/bin/zsh
# Undo scripts/install.sh: remove the Wine half of this setup from the machine.
#
# What it removes:
#   - /Applications/Wine Stable.app  (the Gcenx build install.sh extracted)
#   - the Homebrew winetricks and cabextract formulae
#   - the Wine PATH line install.sh appended to ~/.zshrc
#
# What it deliberately leaves alone:
#   - Rosetta 2       — macOS uses it for far more than Wine, and it is a
#                       system component, not something this repo installed
#   - ~/wine-prefixes — the games installed into them; deleting a prefix loses
#                       save games and everything else inside it
#   - ~/Games         — the native Counter-Strike builds have nothing to do with
#                       Wine, and since mac/vendor-dylibs.sh they do not depend
#                       on Homebrew either
#
# Both of those are printed at the end so it is clear what is still on disk.
#
# Usage:
#   ./uninstall.sh              show the plan, ask, then remove
#   ./uninstall.sh --dry-run    show the plan and stop
#   ./uninstall.sh --yes        no prompt (for scripts)

set -euo pipefail

WINE_APP="/Applications/Wine Stable.app"
ZSHRC="${HOME}/.zshrc"
PATH_LINE='export PATH="/Applications/Wine Stable.app/Contents/Resources/wine/bin:$PATH"'
PATH_COMMENT='# Wine (Gcenx build) CLI tools'
BREW_FORMULAE=(winetricks cabextract)

DRY_RUN=0
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: uninstall.sh [--dry-run] [--yes]

Removes Wine Stable.app, the winetricks/cabextract Homebrew formulae and the
Wine PATH entry in ~/.zshrc. Wine prefixes, ~/Games and Rosetta 2 are kept.
EOF
}

while (( $# )); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "error: unknown option '$1'"; usage >&2; exit 2 ;;
  esac
  shift
done

log()  { print -P "%F{green}==>%f $1"; }
warn() { print -P "%F{yellow}==>%f $1" >&2; }
die()  { print -P "%F{red}error:%f $1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "this setup only exists on macOS"

# --- work out what is actually here -----------------------------------------

# Each entry is one line of the plan; the flags below drive the work itself, so
# the plan and what happens cannot drift apart.
plan=()

remove_app=0
if [[ -d "$WINE_APP" ]]; then
  remove_app=1
  plan+=("delete ${WINE_APP} ($(du -sh "$WINE_APP" 2>/dev/null | cut -f1))")
fi

# A formula another installed formula depends on is left in place: pulling it
# would break that one. freetype, for instance, is not ours to remove.
brew_targets=()
if (( $+commands[brew] )); then
  installed=("${(@f)$(brew list --formula 2>/dev/null || true)}")
  for formula in $BREW_FORMULAE; do
    (( ${installed[(Ie)$formula]} )) || continue
    dependents=("${(@f)$(brew uses --installed --formula "$formula" 2>/dev/null || true)}")

    # winetricks itself depends on cabextract and is going in the same run, so it
    # is not a reason to keep it. Filtered with an explicit loop: a pattern built
    # from a variable is matched literally unless it goes through ${~...}, which
    # is how an earlier version quietly kept cabextract every time.
    blockers=()
    for dependent in $dependents; do
      [[ -n "$dependent" ]] || continue
      (( ${BREW_FORMULAE[(Ie)$dependent]} )) && continue
      blockers+=("$dependent")
    done
    dependents=($blockers)
    if (( ${#dependents} )); then
      plan+=("keep ${formula} — still needed by: ${dependents}")
    else
      brew_targets+=("$formula")
      plan+=("brew uninstall ${formula}")
    fi
  done
fi

edit_zshrc=0
if [[ -f "$ZSHRC" ]] && grep -qF "$PATH_LINE" "$ZSHRC"; then
  edit_zshrc=1
  plan+=("remove the Wine PATH line from ${ZSHRC} (line $(grep -nF "$PATH_LINE" "$ZSHRC" | head -1 | cut -d: -f1))")
fi

if (( ${#plan} == 0 )); then
  log "Nothing to do — Wine, winetricks and the PATH entry are already gone"
  exit 0
fi

log "This will:"
for step in $plan; do
  print "      - ${step}"
done
print "    Kept: Rosetta 2, ~/wine-prefixes, ~/Games"

if (( DRY_RUN )); then
  log "--dry-run: stopping here"
  exit 0
fi

if (( ! ASSUME_YES )); then
  [[ -t 0 ]] || die "not a terminal — re-run with --yes if this is intentional"
  if ! read -q "?    Proceed? [y/N] "; then
    print ""
    die "cancelled"
  fi
  print ""
fi

# Wine holding files open does not block the delete, but the user losing a
# running game to it is worth one warning.
if pgrep -f "Wine Stable.app" >/dev/null 2>&1; then
  warn "something is still running from ${WINE_APP} — quit it first if it matters"
fi

# --- do it -------------------------------------------------------------------

if (( remove_app )); then
  log "Removing ${WINE_APP}"
  # Belt and braces: never let a mangled variable turn this into a wider delete.
  [[ "$WINE_APP" == /Applications/*.app && -d "$WINE_APP" ]] || die "refusing to delete ${WINE_APP}"
  rm -rf "$WINE_APP" || die "could not remove ${WINE_APP} — check permissions"
fi

if (( ${#brew_targets} )); then
  log "Uninstalling ${brew_targets}"
  brew uninstall "${brew_targets[@]}" || warn "brew uninstall did not complete cleanly"
fi

if (( edit_zshrc )); then
  backup="${ZSHRC}.bak-$(date +%Y%m%d%H%M%S)"
  log "Backing up ${ZSHRC} to ${backup:t}"
  cp "$ZSHRC" "$backup"

  log "Removing the Wine PATH entry from ${ZSHRC}"
  # The comment install.sh writes above the line goes too, and so does the blank
  # line it left in front of the pair.
  perl -0pi -e "
    my \$c = quotemeta(q{${PATH_COMMENT}});
    my \$p = quotemeta(q{${PATH_LINE}});
    s/\n*^\$c\n\$p\n/\n/m or s/^\$p\n//m;
  " "$ZSHRC"

  if grep -qF "$PATH_LINE" "$ZSHRC"; then
    warn "the PATH line is still in ${ZSHRC} — remove it by hand (backup: ${backup})"
  fi

  # Hand-added Wine lines are left where they are: this script only owns what
  # install.sh wrote. A stale WINEPREFIX export is worth pointing at though —
  # after this it names a prefix nothing can open, and being set globally it
  # overrides the per-game prefixes this repo works with.
  stale="$(grep -nE '^[^#]*\b(WINEPREFIX|WINEARCH)=' "$ZSHRC" 2>/dev/null || true)"
  if [[ -n "$stale" ]]; then
    warn "${ZSHRC} still sets Wine variables by hand — remove these if you are done with Wine:"
    print -- "$stale" | sed 's/^/      /' >&2
  fi
fi

# --- what is left ------------------------------------------------------------

log "Done. Open a new terminal so the old PATH goes away."

leftovers=()
[[ -d "${HOME}/wine-prefixes" ]] && \
  leftovers+=("~/wine-prefixes ($(du -sh "${HOME}/wine-prefixes" 2>/dev/null | cut -f1)) — game prefixes, kept on purpose")
[[ -d "${HOME}/.wine" ]] && \
  leftovers+=("~/.wine — the default prefix, kept on purpose")
[[ -d "${HOME}/Games" ]] && \
  leftovers+=("~/Games ($(du -sh "${HOME}/Games" 2>/dev/null | cut -f1)) — native builds, nothing to do with Wine")

if (( ${#leftovers} )); then
  print "    Still on disk:"
  for item in $leftovers; do
    print "      - ${item}"
  done
  print "    Delete them by hand if you want them gone."
fi

# Other shell files are not touched by install.sh, but a hand-added line there
# would keep a dead path in PATH and is worth pointing at.
for rc in "${HOME}/.zprofile" "${HOME}/.zshenv" "${HOME}/.bash_profile"; do
  [[ -f "$rc" ]] && grep -qF "Wine Stable.app" "$rc" 2>/dev/null && \
    warn "${rc} also mentions Wine Stable.app — this script only edits ~/.zshrc"
done

exit 0
