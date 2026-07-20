# Wine setup helpers. See README.md for details.

.PHONY: install prefix

# Install Wine (Gcenx build), winetricks, and PATH setup in one shot
install:
	zsh scripts/install.sh

# Create a 64-bit Wine prefix for a game under ~/wine-prefixes/<GAME>.
# Usage:
#   make prefix GAME=counter-strike
#   make prefix GAME=blue-glass-moon FONTS=1   # also install corefonts+cjkfonts
prefix:
ifndef GAME
	$(error GAME is required, e.g. make prefix GAME=counter-strike)
endif
	zsh scripts/new-prefix.sh $(GAME) $(if $(FONTS),--fonts)
