# Wine setup helpers. See README.md for details.

.PHONY: install prefix counter-strike

# Install Wine (Gcenx build), winetricks, and PATH setup in one shot
install:
	zsh scripts/install.sh

# Launch Counter-Strike 1.6 (native Xash3D build, see games/counter-strike/).
# Usage:
#   make counter-strike
#   make counter-strike ARGS="-windowed"
#   make counter-strike ARGS="-dedicated"   # headless server, no client
counter-strike:
	games/counter-strike/run.sh $(ARGS)

# Create a 64-bit Wine prefix for a game under ~/wine-prefixes/<GAME>.
# Usage:
#   make prefix GAME=counter-strike
#   make prefix GAME=blue-glass-moon FONTS=1   # also install corefonts+cjkfonts
prefix:
ifndef GAME
	$(error GAME is required, e.g. make prefix GAME=counter-strike)
endif
	zsh scripts/new-prefix.sh $(GAME) $(if $(FONTS),--fonts)
