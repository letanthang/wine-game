Counter-Strike 1.6 on Xash3D FWGS - native Linux build
======================================================

Self-contained: no installer, no Steam, no Wine. Put this folder anywhere you
can write to (the engine keeps its configs and screenshots in it) and run:

  ./play.sh                 start the game
  ./play.sh -windowed       windowed mode
  ./play.sh +map de_dust2   straight into a match against bots
  BOTS=12 ./play.sh         change the bot count, then play

Requirements
------------
* Debian (or a derivative) on x86. BUILD_INFO.txt says whether this is the
  amd64 or the i386 package; the i386 one also runs on an amd64 system once
  the i386 runtime is installed.
* A desktop session with working OpenGL.
* libfreetype6 and libgl1. SDL2 is already in this folder. play.sh checks for
  missing libraries on every start and prints the exact apt command - it does
  not install anything itself.

Moving the folder
-----------------
Copy it as a tar archive, or with rsync -a / cp -a. The engine's libraries are
symlinks and its binaries need their executable bit; a zip file or a FAT/exFAT
USB stick loses both and the game then fails to start.

Bots
----
An offline match gets bots automatically: cstrike/listenserver.cfg execs
cstrike/bots.cfg on every map start. That file is yours to edit. In-game, press
~ for the console:

  bot_quota 8        keep 8 bots on the server (0 = none)
  bot_add            add one bot
  bot_kick           kick all bots (set bot_quota 0 first, or they come back)
  bot_difficulty 2   0 easy, 1 normal, 2 hard, 3 expert
  bot_knives_only    restrict bot weapons (also *_pistols_only, *_snipers_only)

Console changes last until the map changes, when bots.cfg is re-executed. Edit
cstrike/bots.cfg to make them permanent.

These are the CZ bots built into the ReGameDLL game module - no Metamod, no
YaPB. They use the maps/<map>.nav meshes shipped here. If the console warns that
the navigation data is from a different version of the map, run bot_nav_analyze
to regenerate it (takes a few minutes).

Notes
-----
* Metamod, AMX Mod X and dproto from the original install are NOT included:
  they do not load on Xash3D. Admin/stats plugins are therefore unavailable.
* ./play.sh -dedicated runs a headless server for other Xash3D clients. It has
  no bots: the game module refuses them on a dedicated server.
* Configs are generated on first run, so the first start is the slow one.

See BUILD_INFO.txt for exactly which engine and client builds this package was
assembled from.
