Counter-Strike 1.6 on Xash3D FWGS - native Apple Silicon build
==============================================================

Self-contained: no installer, no Steam, no Wine. This whole folder can be
renamed, moved to another disk, or copied to another Mac and it keeps working.

  Counter-Strike 1.6.app    double-click to play
  play.sh                   the same thing from a terminal, with arguments

  ./play.sh -windowed       windowed mode
  ./play.sh +map de_dust2   straight into a match against bots
  BOTS=12 ./play.sh         change the bot count, then play

Requirements
------------
* Apple Silicon (arm64) Mac on macOS 26.0 or newer. The engine itself needs only
  14.8, but the CS16Client libraries in cstrike/cl_dlls are built against 26.0;
  on an older system the game starts and then reports that the "MenuFactory"
  object is unavailable.
* Nothing else - the engine, the client and all assets are in this folder.

Bots
----
An offline match gets bots automatically: cstrike/listenserver.cfg execs
cstrike/bots.cfg on every map start. That file is yours to edit and nothing
overwrites it. In-game, press ~ for the console:

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

Moving this folder to another Mac
---------------------------------
Copy it as a ZIP archive. Copying onto a FAT/exFAT drive loses the executable
bits and the game will not start afterwards.

macOS quarantines anything that arrives by download or AirDrop, and these
binaries are not signed by an identified developer, so the first launch will be
blocked. Clear the quarantine flag on the whole folder once:

  xattr -dr com.apple.quarantine "/path/to/this/folder"

Right-click the app and choose Open also works, but has to be repeated for each
blocked binary, so the command above is easier.

Troubleshooting
---------------
Double-clicking the app does nothing visible: everything it prints goes to

  ~/Library/Logs/counter-strike-16.log

which is overwritten on every launch. The last lines say what went wrong.

The multiplayer browser works (Xash3D speaks GoldSrc protocol 48), but servers
with strict anti-cheat may reject a non-GoldSrc client. LAN play between Xash3D
clients is fine.
