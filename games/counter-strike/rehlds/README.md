# Counter-Strike 1.6 dedicated server on Debian (ReHLDS)
Server-side counterpart to the macOS client in `games/counter-strike/`. The
client there is a native arm64 **Xash3D FWGS** build — it plays fine but cannot
host a proper dedicated server (its `-dedicated` mode never even registers the
bot commands). This directory builds a real dedicated server on Debian from the
**ReHLDS** stack.

Scope: Counter-Strike 1.6 only. Nothing here touches Wine, the Wine prefixes, or
the Sikarugir wrapper.
## Distribution flow

The payload is 32-bit x86 and can only be built and run on x86_64 — which is what
GitHub's runners are. So the Mac never builds or runs the server; CI does the
packaging and the target host only pulls.

```
GitHub  ──►  GitHub Actions (ubuntu-latest, x86_64)
                 │  .github/workflows/cs16-server-image.yml
                 │
                 ├─ install SteamCMD
                 ├─ download HLDS (app 90, steam_legacy branch)
                 ├─ ReHLDS + ReGameDLL       (GPG-verified)
                 ├─ Metamod-R + ReAPI + ReUnion + AMX Mod X
                 ├─ plugins/*.amxx + cfg/*
                 ├─ build linux/amd64 image  (docker/Dockerfile)
                 └─ smoke-test: engine, Metamod-R, AMXX, ReGameDLL all load
                       │
                       ▼
              Docker Hub: docker.io/<user>/cs16-rehlds
                       │
                       ▼
              Target server (Debian x86_64)
                       ├── docker pull
                       └── docker run   ── rcon password + ReUnion salt
                                           generated at run time, not baked in
```

Everything below documents the same steps, whether you run them through CI, in
Docker locally on an x86_64 box, or straight on a VPS with `install.sh`.

## What gets installed and why

| Component | Role | Source |
| --- | --- | --- |
| **ReHLDS** | Reverse-engineered, bug-fixed HLDS engine (`engine_i486.so`) | [rehlds/ReHLDS](https://github.com/rehlds/ReHLDS) |
| **ReGameDLL_CS** | Reverse-engineered CS game DLL (`cs.so`), ships the zBot AI | [rehlds/ReGameDLL_CS](https://github.com/rehlds/ReGameDLL_CS) |
| **Metamod-R** | Plugin loader, required by everything below | [rehlds/Metamod-R](https://github.com/rehlds/Metamod-R) |
| **ReUnion** | Lets non-Steam protocol 47/48 clients join — including Xash3D | [rehlds/ReUnion](https://github.com/rehlds/ReUnion) |
| **AMX Mod X** | Admin commands, kick/ban, map votes, stats | [amxmodx.org](https://www.amxmodx.org/downloads-new.php) |
| **ReAPI** | AMXX module exposing the ReHLDS/ReGameDLL API to plugins | [rehlds/ReAPI](https://github.com/rehlds/ReAPI) |
| **zBot** | Bots, the same ones the macOS client uses offline | ReGameDLL + `bot_profiles.zip` |

Base game content comes from **SteamCMD app 90**, which is free and anonymous.

Exact pinned versions live in [`versions.env`](versions.env) — they were verified
on 2026-07-28, including the internal layout of every archive. Override any of
them from the environment to move up or down a version.

### Why these sources

The `rehlds` organisation is the reference open-source GoldSrc server stack: the
engine and game DLL were reconstructed from the original binaries' debug info,
they are actively maintained, and **their release archives are GPG-signed**
(key `63547829004F07716F7BE4856C32C4282E60FB67`). `install.sh` verifies those
signatures and aborts if they do not check out. Everything else is fetched over
HTTPS from the project's own release hosting.

### The two hard constraints

1. **Pre-anniversary engine only.** ReHLDS supports HLDS engine builds `<= 8684`,
   so the game files must come from the `steam_legacy` branch:
   `app_update 90 -beta steam_legacy validate`. The current default branch ships
   the 25th-anniversary build, which ReHLDS will not run.
2. **32-bit x86.** Everything is i386 — engine, game DLL and every plugin. On
   Debian amd64 that means enabling multi-arch (`dpkg --add-architecture i386`);
   `install.sh` and the Dockerfile both do it. On arm64 there are no native
   binaries at all and no way to make some: use an x86_64 host.

## Make targets

This directory has its own `Makefile` — run `make` (or `make help`) in it:

| Target | What it does |
| --- | --- |
| `make install` | run `install.sh` (bare-metal Debian) |
| `make start` | run `start.sh` in the foreground |
| `make build` | `docker buildx build --platform linux/amd64 --load` → `cs16-rehlds:local` |
| `make push REGISTRY=docker.io/<user> TAG=latest` | build and push to a registry |
| `make up` / `down` / `restart` | drive `docker/docker-compose.yml` |
| `make logs` / `shell` / `status` | inspect a running container |
| `make clean` | drop the image and the log volume |

Overridable: `IMAGE`, `TAG`, `REGISTRY`, `PLATFORM`.

## Quick start on a Debian VPS (x86_64)

```sh
# On the server, as a normal user with sudo rights:
git clone <this repo> ~/wine-game
cd ~/wine-game/games/counter-strike/rehlds

./install.sh          # ~1 GB download, several SteamCMD passes, ~10 min
./start.sh            # foreground, Ctrl+C to stop
```

`install.sh` is safe to re-run — it re-applies the binaries and configs but
keeps the generated rcon password and ReUnion salt.

Useful overrides:

```sh
SERVER_DIR=/srv/cs16 ./install.sh     # install somewhere else
SKIP_GPG=1 ./install.sh               # no network access to keyservers
GAME_SRC=/path/to/cs16 ./install.sh   # reuse existing game files, skip SteamCMD
MAP=cs_office MAXPLAYERS=24 ./start.sh
```

### Run it as a service

```sh
sudo useradd -m -d /home/cs16 cs16          # dedicated unprivileged user
sudo -u cs16 -i                             # install as that user, then exit
sudo cp systemd/cs16-rehlds.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cs16-rehlds
journalctl -u cs16-rehlds -f
```

Adjust the paths in the unit file if you did not install into
`/home/cs16/cs16-server` with the repo at `/home/cs16/wine-game`.

### Firewall

```sh
sudo ufw allow 27015/udp     # game traffic
sudo ufw allow 27015/tcp     # rcon
```

## Docker (x86_64 hosts only — it does not run on Apple Silicon)

```sh
make counter-strike-server              # from the repo root
# equivalent to:
cd games/counter-strike/rehlds/docker && docker compose up --build
```

The image is `linux/amd64` with i386 multi-arch enabled inside — an x86_64 kernel
runs the 32-bit GoldSrc binaries natively. On any x86_64 host (Linux, Intel Mac,
CI) that just works. **On Apple Silicon it does not** — see below. The real
deployment target is a Debian x86_64 host either way.

### Why it fails on Apple Silicon (tested 2026-07-28/29 on an M4)

GoldSrc is 32-bit x86 and Rosetta only emulates x86_64, so on arm64 the 32-bit
binaries fall through to QEMU user-mode emulation — and **Valve's Steam libraries
do not survive that**. This holds for `linux/amd64` and `linux/386` images alike;
the tests below were run with the latter:

1. SteamCMD segfaults immediately: `Loading Steam API… Segmentation fault`, every
   pass. So the game files cannot be downloaded inside the container.
2. Even with the files supplied from outside, the engine starts, loads
   everything — Metamod-r 1.3.0.149, AMX Mod X 1.10, ReGameDLL 5.30.0.814, map
   `de_dust2`, spawn points — and then dies at Steam init:

   ```
   [S_API FAIL] SteamAPI_Init() failed; SteamAPI_IsSteamRunning() failed.
   Fatal error: futex robust_list not initialized by pthreads
   qemu: uncaught target signal 11 (Segmentation fault) - core dumped
   ```

   Ruled out as causes: missing `.nav` files (copied all 27 in — same crash),
   bots (`bot_quota 0` — same crash), Docker's seccomp profile
   (`seccomp:unconfined` — same crash), `-insecure +sv_lan 1` (same crash).

On Apple Silicon the container therefore stops at step 1 — SteamCMD cannot fetch
the game. During development the installer was verified anyway by handing it the
files from outside (`GAME_SRC`), which is how the crash in step 2 was found; that
detour is not part of the normal flow. Run the container on the x86_64 host that
will actually serve the game — a Debian VPS with Docker installed works fine:

```sh
git clone <this repo> ~/wine-game
cd ~/wine-game && make counter-strike-server
```

### Setting up CI (one-time)

The workflow [`.github/workflows/cs16-server-image.yml`](../../../.github/workflows/cs16-server-image.yml)
builds on every push that touches this directory. To make it *publish*, add two
repository secrets — a Docker Hub **access token**, not the account password:

```sh
gh secret set DOCKERHUB_USERNAME --body '<user>'
gh secret set DOCKERHUB_TOKEN    --body '<token from hub.docker.com/settings/security>'
```

Until those exist the workflow still runs: it builds the image, loads it locally
and smoke-tests it, then stops without pushing. Tags produced: `latest` (default
branch), `sha-<short>` for every commit, and `cs16-v*` git tags.

### Running the published image (the normal path)

The target server needs nothing but Docker:

```sh
docker run -d --name cs16 -p 27015:27015/udp -p 27015:27015/tcp \
  -e RCON_PASSWORD=... -e REUNION_SALT=... \
  docker.io/<user>/cs16-rehlds:latest

# or with this repo's compose file:
CS16_IMAGE=docker.io/<user>/cs16-rehlds:latest docker compose up -d
```

### How the image is put together

- **Everything is baked in at build time** — game files and the full stack — so
  the image is self-contained (~1.5 GB) and starts in seconds.
- **No credentials are baked in.** The build runs `install.sh` with
  `NO_SECRETS=1`, leaving `__RCON_PASSWORD__` and `__STEAMID_HASH_SALT__`
  placeholders; `docker/entrypoint.sh` fills them from `$RCON_PASSWORD` /
  `$REUNION_SALT`, or with random values per run. Set both in production —
  otherwise the rcon password changes on every restart and ReUnion hands players
  new SteamIDs, which breaks AMXX admin entries.
- The build **fails** rather than shipping a broken image: the Dockerfile
  asserts that the engine, `cs.so`, Metamod-R, ReUnion, AMXX, ReAPI and the
  patched `liblist.gam` are all in place.
- `cfg/` is mounted by `docker-compose.yml`, so config tweaks need a restart,
  not a rebuild. Drop that mount to run exactly what the image shipped with.

### Reusing game files you already have (`GAME_SRC`, optional)

If a host already has the HLDS files, `install.sh` can copy them instead of
downloading ~870 MB again:

```sh
GAME_SRC=/path/to/hlds ./install.sh
```

> This must be a **Linux HLDS server install** (SteamCMD app 90). A client
> install is not enough: it lacks `libsteam_api.so`, and the engine then dies
> with `Unable to load engine, image is corrupt`. Tested 2026-07-28 with the
> Xash3D client files; `install.sh` warns when that file is missing.

## Connecting from the macOS Xash3D client

```sh
games/counter-strike/run.sh
# then in the console (~):
connect <server-ip>:27015
```

The Xash3D client is a non-Steam protocol 48 client: it has no Steam auth
ticket, which a stock HLDS rejects. **ReUnion is what lets it in** — `install.sh`
sets `cid_NoSteam48 = 3` and `cid_NoSteam47 = 3` in `cstrike/reunion.cfg`
(the shipped defaults are `5`, meaning "reject"), so such clients are admitted
and given a `STEAM_` id derived from their IP.

Caveats worth knowing before you debug for an hour:

- Xash3D FWGS also supports an explicit GoldSrc connect form,
  `connect <ip>:27015 gs`. Try it if the plain form misbehaves.
- FWGS documents that some GoldSrc servers flag Xash3D clients as fake clients.
  This is our own server, so nothing is deliberately blocking them, but this
  exact client/server pairing has not been confirmed end-to-end yet — do it once
  the server is up on the VPS.
- A regular Steam CS 1.6 client connects with no ReUnion involvement at all.

## Bots

zBot (the CZ bot AI built into ReGameDLL) is enabled out of the box. The one
non-obvious requirement:

> `bot_enable 1` must be in **`cstrike/game_init.cfg`**, not `server.cfg`.

On a dedicated server the game DLL decides whether bots are allowed *while it is
initialising*, and `game_init.cfg` is the only config read that early. Setting
`bot_enable` in `server.cfg` is too late and the bot commands never appear
(`Unknown command "bot_quota"`). This was confirmed by disassembling
`UTIL_AreBotsAllowed` in the client's own game DLL: listen servers always allow
bots, dedicated servers require this cvar.

Everything else lives in [`cfg/bots.cfg`](cfg/bots.cfg) — `bot_quota`,
`bot_difficulty`, `bot_quota_mode fill` (bots top the server up as humans join),
and the same knobs the client-side `games/counter-strike/bots.cfg` uses. Console
commands (`bot_add`, `bot_kick`, …) are documented in
[`../README.md`](../README.md#console-commands-press--in-game).

**Navigation meshes.** zBot needs `cstrike/maps/<map>.nav`. The SteamCMD download
does **not** include them (verified 2026-07-28: 25 maps, zero `.nav`), so zBot
generates one the first time it plays a map — several minutes of CPU per map.
`install.sh` warns when none are found. Much faster to copy them from the Mac
client, which has all 27:

```sh
scp ~/Games/cs16/cstrike/maps/*.nav <server>:~/cs16-server/cstrike/maps/
```

## What has been verified so far

Verified on 2026-07-28/29 by running the installer inside an i386 container on
the M4 (the image was `linux/386` at the time; it is `linux/amd64` now):

- the full pipeline: dependencies, game files, ReHLDS, ReGameDLL, zBot data,
  Metamod-R, ReUnion, AMX Mod X, `liblist.gam` patch, configs, `.nav` check;
- **GPG signatures of ReHLDS and ReGameDLL genuinely check out**
  (`Good signature from "ReHLDS Team <team@rehlds.dev>"`);
- the engine loads the whole stack: `Protocol version 48`, Metamod-r,
  AMX Mod X, `ReGameDLL version: 5.30.0.814-dev`, `Mapchange to de_dust2`.

Not yet verified, because the engine cannot stay up under QEMU: bots actually
joining a dedicated server, `meta list` showing ReUnion and ReAPI as `RUN`, and
the Xash3D client connecting through ReUnion. The CI workflow re-checks the
first half on real x86_64 hardware (it smoke-tests every published image); the
rest needs the Debian host and the checks below.

ReAPI and the `plugins/` mechanism were added after that test run and have not
been through a build yet — the first CI run will tell.

## Verifying an install

In the server console (or via `rcon`):

```
meta list        // expect Reunion and AMX Mod X both in state RUN
version          // expect "ReHLDS version: 3.15.0.896"
bot_quota        // must be a known command; bots should already be in-game
status           // lists players, [BOT]-prefixed ones included
```

If `meta list` is empty, `liblist.gam` is not pointing at Metamod — check that
it reads `gamedll_linux "addons/metamod/metamod_i386.so"` (the original is kept
as `liblist.gam.orig`).

## Layout

```
rehlds/
├── install.sh        # one-shot installer (Debian, bash — not macOS/zsh)
├── start.sh          # launches the engine with sane defaults
├── versions.env      # pinned versions + URLs, all overridable
├── cfg/              # server.cfg, bots.cfg, game_init.cfg, plugins.ini, mapcycle
├── plugins/          # drop custom .amxx files here (see plugins/README.md)
├── systemd/          # cs16-rehlds.service
└── docker/           # Dockerfile (build-time install), compose, entrypoint
```

CI workflow: [`.github/workflows/cs16-server-image.yml`](../../../.github/workflows/cs16-server-image.yml)

Installed server layout (default `~/cs16-server`):

```
cs16-server/
├── hlds_run, hlds_linux, engine_i486.so   # engine_i486.so.orig-valve = the original
└── cstrike/
    ├── dlls/cs.so                         # ReGameDLL (cs.so.orig-valve = original)
    ├── liblist.gam                        # points at Metamod (liblist.gam.orig = original)
    ├── server.cfg, bots.cfg, game_init.cfg, reunion.cfg
    ├── maps/*.bsp + *.nav
    └── addons/
        ├── metamod/{metamod_i386.so,config.ini,plugins.ini}
        ├── reunion/reunion_mm_i386.so
        └── amxmodx/...
```

## Security notes

- `install.sh` generates a random rcon password into `cstrike/server.cfg` and a
  random `SteamIdHashSalt` into `cstrike/reunion.cfg`, and preserves both on
  re-runs. Neither file belongs in git — only the templates in `cfg/` are
  tracked, and the repo copy carries a `__RCON_PASSWORD__` placeholder.
- Run the server as an unprivileged user (the systemd unit assumes `cs16`).
- `sv_lan 1` in `server.cfg` turns the server LAN-only if you do not want it
  reachable from the internet.
