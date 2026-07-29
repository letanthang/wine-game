# Custom AMX Mod X plugins

Drop compiled `.amxx` files in this directory. On the next `install.sh` run (or
the next image build) they are copied into
`cstrike/addons/amxmodx/plugins/` and appended to
`cstrike/addons/amxmodx/configs/plugins.ini`, so AMXX loads them at map start.

Nothing here by default — AMX Mod X already ships its own base plugins (admin
commands, kick/ban, map voting, stats).

## Notes

- **Compiled only.** `.sma` sources are not compiled by `install.sh`. Build them
  with AMXX's `amxxpc` (or the web compiler) and commit the `.amxx` output.
- **ReAPI is available**, so plugins written against `reapi.inc` work. The
  includes are installed under `cstrike/addons/amxmodx/scripting/include/`.
- Plugins are appended to `plugins.ini` only if the exact filename is not
  already listed, so re-running the installer will not duplicate entries.
- To remove a plugin, delete the `.amxx` here *and* its line in the server's
  `plugins.ini` — the installer never deletes entries.
