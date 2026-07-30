# syntax=docker/dockerfile:1
#
# STEP 2 of two — package the server files prepared by fetch.sh.
#
#   ./fetch.sh   →   local/server-files/   →   this Dockerfile   →   image
#
# The build downloads nothing: no SteamCMD, no GitHub releases, no network at
# all. That keeps it fast, reproducible, and buildable on any machine, including
# Apple Silicon where SteamCMD cannot run.
#
# Run `./fetch.sh` (or `make fetch`) first — without local/server-files/ the COPY
# below fails.
#
#   docker build -f docker/Dockerfile -t cs16-rehlds .    # context = rehlds/
#
# The server itself is 32-bit x86 and still needs an x86_64 host to RUN.
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/cs16 \
    SERVER_DIR=/opt/cs16-server \
    SETUP_DIR=/opt/rehlds-setup

# i386 multi-arch: the engine, the game DLL and every plugin are 32-bit.
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates procps \
      lib32gcc-s1 lib32stdc++6 libc6:i386 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -d /home/cs16 -s /bin/bash cs16 \
 && mkdir -p "${SERVER_DIR}" "${SETUP_DIR}" \
 && chown -R cs16:cs16 "${SERVER_DIR}" "${SETUP_DIR}"

# The big, rarely-changing layer.
COPY --chown=cs16:cs16 local/server-files/ /opt/cs16-server/

# Scripts and configs: small and edited often, so they come last. entrypoint.sh
# also needs install.sh for its empty-volume fallback.
COPY --chown=cs16:cs16 install.sh start.sh versions.env /opt/rehlds-setup/
COPY --chown=cs16:cs16 cfg/ /opt/rehlds-setup/cfg/
COPY --chown=cs16:cs16 docker/entrypoint.sh /opt/rehlds-setup/docker/entrypoint.sh

# Fail the build, not the deployment, if step 1 produced an incomplete tree.
RUN test -f "${SERVER_DIR}/engine_i486.so" \
 && test -f "${SERVER_DIR}/libsteam_api.so" \
 && test -f "${SERVER_DIR}/cstrike/dlls/cs.so" \
 && test -f "${SERVER_DIR}/cstrike/addons/metamod/metamod_i386.so" \
 && test -f "${SERVER_DIR}/cstrike/addons/reunion/reunion_mm_i386.so" \
 && test -f "${SERVER_DIR}/cstrike/addons/amxmodx/dlls/amxmodx_mm_i386.so" \
 && test -f "${SERVER_DIR}/cstrike/addons/amxmodx/modules/reapi_amxx_i386.so" \
 && grep -q 'addons/metamod/metamod_i386.so' "${SERVER_DIR}/cstrike/liblist.gam" \
 && grep -q '__RCON_PASSWORD__' "${SERVER_DIR}/cstrike/server.cfg" \
 && test -f "${SERVER_DIR}/BUILD_INFO"

USER cs16

LABEL org.opencontainers.image.title="Counter-Strike 1.6 dedicated server (ReHLDS)" \
      org.opencontainers.image.description="ReHLDS + ReGameDLL_CS + Metamod-R + ReAPI + ReUnion + AMX Mod X + zBot" \
      org.opencontainers.image.licenses="MIT"
# Component and game-build versions:
#   docker run --rm --entrypoint cat <image> /opt/cs16-server/BUILD_INFO

EXPOSE 27015/udp 27015/tcp

ENTRYPOINT ["/opt/rehlds-setup/docker/entrypoint.sh"]
