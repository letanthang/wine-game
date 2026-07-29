# Self-contained CS 1.6 ReHLDS server image.
#
# The whole stack is baked in at build time — SteamCMD, HLDS game files, ReHLDS,
# ReGameDLL, Metamod-R, ReAPI, ReUnion, AMX Mod X, plugins — so the target host
# only needs `docker pull` + `docker run`. Expect ~1.5 GB.
#
# GoldSrc is 32-bit x86 only, so this is a linux/386 image and it must be BUILT
# and RUN on x86_64 (GitHub Actions runners, a Debian VPS, an Intel Mac). It does
# not work on Apple Silicon: SteamCMD and the engine both crash under the QEMU
# emulation arm64 would need — see README.md.
#
#   docker build -f docker/Dockerfile -t cs16-rehlds .     # context = rehlds/
FROM --platform=linux/386 debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/cs16 \
    SERVER_DIR=/opt/cs16-server \
    STEAMCMD_DIR=/opt/steamcmd \
    SETUP_DIR=/opt/rehlds-setup

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip tar gnupg libstdc++6 libgcc-s1 procps \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -d /home/cs16 -s /bin/bash cs16 \
 && mkdir -p "${SERVER_DIR}" "${STEAMCMD_DIR}" \
 && chown -R cs16:cs16 "${SERVER_DIR}" "${STEAMCMD_DIR}"

COPY --chown=cs16:cs16 . /opt/rehlds-setup/

USER cs16

# Dependencies are already installed above; this fetches the game and the whole
# ReHLDS stack, verifies GPG signatures, and writes the configs.
# NO_SECRETS keeps the rcon password and the ReUnion salt as placeholders, so a
# published image does not ship credentials — entrypoint.sh fills them per run.
RUN SKIP_DEPS=1 NO_SECRETS=1 /opt/rehlds-setup/install.sh \
 && rm -rf "${STEAMCMD_DIR}"/linux32/steamapps "${HOME}/.steam" "${HOME}/Steam" \
 && rm -rf "${SERVER_DIR}/steamapps"

# Sanity-check the layers that matter, so a broken image fails the build rather
# than the deployment.
RUN test -f "${SERVER_DIR}/engine_i486.so" \
 && test -f "${SERVER_DIR}/libsteam_api.so" \
 && test -f "${SERVER_DIR}/cstrike/dlls/cs.so" \
 && test -f "${SERVER_DIR}/cstrike/addons/metamod/metamod_i386.so" \
 && test -f "${SERVER_DIR}/cstrike/addons/reunion/reunion_mm_i386.so" \
 && test -f "${SERVER_DIR}/cstrike/addons/amxmodx/dlls/amxmodx_mm_i386.so" \
 && test -f "${SERVER_DIR}/cstrike/addons/amxmodx/modules/reapi_amxx_i386.so" \
 && grep -q 'addons/metamod/metamod_i386.so' "${SERVER_DIR}/cstrike/liblist.gam"

EXPOSE 27015/udp 27015/tcp

ENTRYPOINT ["/opt/rehlds-setup/docker/entrypoint.sh"]
