# CS 1.6 ReHLDS server. See README.md.
#
# The image is linux/amd64 with 32-bit multi-arch inside — GoldSrc itself is
# i386-only — so building and running it requires an x86_64 host. See the note at
# the bottom of this file for why there is no arm64 target.

IMAGE   ?= cs16-rehlds
TAG     ?= local
REGISTRY ?=
PLATFORM ?= linux/amd64
COMPOSE  := docker compose -f docker/docker-compose.yml

# Full reference, e.g. docker.io/<user>/cs16-rehlds:latest
IMAGE_REF := $(if $(REGISTRY),$(REGISTRY)/,)$(IMAGE):$(TAG)

.PHONY: help build push up down restart logs shell status install start clean

help:
	@echo "Server (run these on a Debian x86_64 host):"
	@echo "  make install                 install the stack into ~/cs16-server"
	@echo "  make start                   run the server in the foreground"
	@echo ""
	@echo "Docker (x86_64 host required):"
	@echo "  make build                   buildx build $(IMAGE_REF) ($(PLATFORM))"
	@echo "  make push REGISTRY=docker.io/<user> TAG=latest"
	@echo "  make up / down / restart     run it through docker compose"
	@echo "  make logs / shell / status   inspect a running container"
	@echo "  make clean                   remove the image and the log volume"
	@echo ""
	@echo "Variables: IMAGE=$(IMAGE) TAG=$(TAG) PLATFORM=$(PLATFORM) REGISTRY=$(REGISTRY)"

# --- bare-metal (Debian) --------------------------------------------------

install:
	./install.sh

start:
	./start.sh

# --- docker ----------------------------------------------------------------

# buildx with --load so the result lands in the local docker images list.
build:
	docker buildx build \
	  --platform $(PLATFORM) \
	  --file docker/Dockerfile \
	  --tag $(IMAGE_REF) \
	  --load \
	  .

# Publish. REGISTRY is required, and you must be logged in to it.
push:
ifndef REGISTRY
	$(error REGISTRY is required, e.g. make push REGISTRY=docker.io/<user> TAG=latest)
endif
	docker buildx build \
	  --platform $(PLATFORM) \
	  --file docker/Dockerfile \
	  --tag $(IMAGE_REF) \
	  --push \
	  .

up:
	CS16_IMAGE=$(IMAGE_REF) $(COMPOSE) up -d

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f --tail 100

shell:
	$(COMPOSE) exec cs16 bash

status:
	$(COMPOSE) ps

clean:
	-$(COMPOSE) down -v
	-docker image rm $(IMAGE_REF)

# --- why there is no arm64 target -----------------------------------------
#
# Every binary in this stack is 32-bit x86 and nothing else exists upstream:
# engine_i486.so (ReHLDS), cs.so (ReGameDLL), metamod_i386.so, reunion_mm_i386.so,
# amxmodx_mm_i386.so, reapi_amxx_i386.so. `--platform linux/arm64` would only
# change the base image; buildx does not recompile anything, so the binaries
# inside would still be i386 and would still run through QEMU — which is exactly
# what crashes (see README.md). Rosetta cannot help either: it emulates x86_64
# only, never 32-bit x86.
# Build on x86_64 — GitHub Actions does it for you.
