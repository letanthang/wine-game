# Wine setup helpers. See README.md for details.

.PHONY: install prefix counter-strike counter-strike-offline counter-strike-server

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

# Start an offline match against bots straight away (CZ bots from ReGameDLL).
# Usage:
#   make counter-strike-offline                        # de_dust2, 8 bots
#   make counter-strike-offline MAP=cs_office BOTS=12
# Bot settings live in games/counter-strike/bots.cfg.
counter-strike-offline:
	BOTS=$(or $(BOTS),8) games/counter-strike/run.sh +map $(or $(MAP),de_dust2) $(ARGS)

# Build and run the CS 1.6 ReHLDS dedicated server in Docker (linux/386).
# Works on x86_64 hosts only: under QEMU on Apple Silicon the installer runs but
# the engine crashes in Valve's Steam init. The real deployment target is a
# Debian x86_64 host — see games/counter-strike/rehlds/README.md.
counter-strike-server:
	docker compose -f games/counter-strike/rehlds/docker/docker-compose.yml up --build

# Create a 64-bit Wine prefix for a game under ~/wine-prefixes/<GAME>.
# Usage:
#   make prefix GAME=counter-strike
#   make prefix GAME=blue-glass-moon FONTS=1   # also install corefonts+cjkfonts
prefix:
ifndef GAME
	$(error GAME is required, e.g. make prefix GAME=counter-strike)
endif
	zsh scripts/new-prefix.sh $(GAME) $(if $(FONTS),--fonts)
