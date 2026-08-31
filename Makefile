# Wine setup helpers. See README.md for details.

.PHONY: install uninstall prefix counter-strike counter-strike-offline counter-strike-dedicated counter-strike-server counter-strike-windows counter-strike-standalone counter-strike-mac counter-strike-vendor

# Install Wine (Gcenx build), winetricks, and PATH setup in one shot
install:
	zsh scripts/install.sh

# Undo `make install`: remove Wine Stable.app, the winetricks/cabextract Homebrew
# formulae and the Wine PATH line in ~/.zshrc. Wine prefixes (~/wine-prefixes),
# ~/Games and Rosetta 2 are kept — it prints what is left afterwards.
# Usage:
#   make uninstall              show the plan, ask, then remove
#   make uninstall ARGS=--dry-run
#   make uninstall ARGS=--yes   no prompt
uninstall:
	zsh scripts/uninstall.sh $(ARGS)

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

# Run the Xash3D engine itself as a headless dedicated server. Only Xash3D /
# CS16Client clients can join it, and it has no bots and no Metamod/AMXX — see
# "Dedicated server" in games/counter-strike/README.md before using this.
# Usage:
#   make counter-strike-dedicated                                      # de_dust2, 12 slots, :27015
#   make counter-strike-dedicated MAP=cs_office PORT=27016 MAXPLAYERS=16
counter-strike-dedicated:
	games/counter-strike/run.sh -dedicated \
		-port $(or $(PORT),27015) \
		+maxplayers $(or $(MAXPLAYERS),12) \
		+map $(or $(MAP),de_dust2) $(ARGS)

# Build the CS 1.6 ReHLDS dedicated server image, in two steps:
#   1. fetch  — download and assemble the server files on this host
#   2. build  — package them into a linux/amd64 image (no network)
# Building works anywhere, including Apple Silicon; running the server needs an
# x86_64 host. See games/counter-strike/rehlds/README.md.
counter-strike-server:
	$(MAKE) -C games/counter-strike/rehlds all

# Assemble ~/Games/cs16-mac from scratch: the Xash3D FWGS arm64 engine and
# CS16Client are downloaded, the game assets come from a local install
# (~/Games/assets), and install-standalone.sh finishes the folder off.
# Usage:
#   make counter-strike-mac                 # full build, then the standalone install
#   make counter-strike-mac ARGS=--force    # overwrite an existing ~/Games/cs16-mac
#   make counter-strike-mac ARGS=--slim     # skip the 430 MB valve/ assets
#   make counter-strike-mac SRC=~/Games/assets
counter-strike-mac:
	$(if $(SRC),SRC=$(SRC) )games/counter-strike/mac/build.sh $(ARGS)

# Make ~/Games/cs16-mac a standalone install: a play.sh launcher, a double-clickable
# Counter-Strike 1.6.app and a README, none of which need this repo afterwards.
# Safe to re-run; it leaves cstrike/bots.cfg alone.
# Usage:
#   make counter-strike-standalone                      # ~/Games/cs16-mac/Counter-Strike 1.6.app
#   make counter-strike-standalone OFFLINE=1            # "(Bots).app", straight into de_dust2
#   make counter-strike-standalone OFFLINE=1 MAP=cs_office
#   make counter-strike-standalone ARGS=--reset-bots    # restore this repo's bots.cfg
counter-strike-standalone:
	games/counter-strike/install-standalone.sh $(if $(OFFLINE),--offline $(MAP)) $(ARGS)

# Copy every non-system library ~/Games/cs16-mac links against into the folder
# itself, so it also runs on a Mac without Homebrew. build.sh already does this;
# this target repairs a folder that was assembled before it did. It has to run on
# a Mac that HAS the libraries (this one), not on the machine that is missing
# them. See "Portability: vendored libraries" in games/counter-strike/README.md.
# Usage:
#   make counter-strike-vendor
#   make counter-strike-vendor GAME_DIR=~/Games/cs16-mac-copy
counter-strike-vendor:
	games/counter-strike/mac/vendor-dylibs.sh $(if $(GAME_DIR),$(GAME_DIR))

# Assemble a portable Windows build of CS 1.6 on Xash3D into ~/Games/cs16-windows.
# Copy the folder (or the zip) to a Windows PC and run play.bat — no installer.
# Usage:
#   make counter-strike-windows                 # full package, ~822 MB
#   make counter-strike-windows ZIP=1           # plus ~/Games/cs16-windows.zip
#   make counter-strike-windows SLIM=1 ZIP=1    # without the Half-Life valve/ assets
# See games/counter-strike/windows/README.md.
counter-strike-windows:
	games/counter-strike/windows/build.sh --force \
		$(if $(SLIM),--slim) $(if $(ZIP),--zip) $(if $(REFRESH),--refresh) $(ARGS)

# Create a 64-bit Wine prefix for a game under ~/wine-prefixes/<GAME>.
# Usage:
#   make prefix GAME=counter-strike
#   make prefix GAME=blue-glass-moon FONTS=1   # also install corefonts+cjkfonts
prefix:
ifndef GAME
	$(error GAME is required, e.g. make prefix GAME=counter-strike)
endif
	zsh scripts/new-prefix.sh $(GAME) $(if $(FONTS),--fonts)
