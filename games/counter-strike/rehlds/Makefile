# CS 1.6 ReHLDS server. See README.md.
#
# Two steps:
#   make fetch    download and assemble local/server-files/  (runs on this host)
#   make build    package that tree into a Docker image      (downloads nothing)
#
# The image is linux/amd64 with 32-bit multi-arch inside; GoldSrc itself is
# i386-only, so an x86_64 host is required to RUN the server. Building works
# anywhere, including Apple Silicon.

IMAGE    ?= cs16-rehlds
TAG      ?= local
REGISTRY ?=
PLATFORM ?= linux/amd64
COMPOSE  := docker compose -f docker/docker-compose.yml

# Full reference, e.g. docker.io/<user>/cs16-rehlds:latest
IMAGE_REF := $(if $(REGISTRY),$(REGISTRY)/,)$(IMAGE):$(TAG)

SERVER_FILES := local/server-files

.PHONY: help all fetch build push up down restart logs shell status install start clean distclean

help:
	@echo "Two-step build:"
	@echo "  make fetch                   download + assemble $(SERVER_FILES)"
	@echo "  make build                   package it into $(IMAGE_REF) ($(PLATFORM))"
	@echo "  make all                     both"
	@echo "  make push REGISTRY=docker.io/<user> TAG=latest"
	@echo ""
	@echo "Run it:"
	@echo "  make up / down / restart     via docker compose"
	@echo "  make logs / shell / status   inspect a running container"
	@echo ""
	@echo "Bare metal (on a Debian x86_64 server):"
	@echo "  make install                 install into ~/cs16-server"
	@echo "  make start                   run in the foreground"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean                   remove the image and the log volume"
	@echo "  make distclean               also delete $(SERVER_FILES)"
	@echo ""
	@echo "Variables: IMAGE=$(IMAGE) TAG=$(TAG) PLATFORM=$(PLATFORM) REGISTRY=$(REGISTRY)"

all: fetch build

# --- step 1: prepare the files ---------------------------------------------

fetch:
	./fetch.sh

# --- step 2: package them ---------------------------------------------------

# Guard rather than let COPY fail with a bare "not found".
check-files:
	@test -f $(SERVER_FILES)/BUILD_INFO || { \
	  echo "error: $(SERVER_FILES) is missing or incomplete — run 'make fetch' first" >&2; \
	  exit 1; }

build: check-files
	docker buildx build \
	  --platform $(PLATFORM) \
	  --file docker/Dockerfile \
	  --tag $(IMAGE_REF) \
	  --load \
	  .

# Publish. REGISTRY is required, and you must be logged in to it.
push: check-files
ifndef REGISTRY
	$(error REGISTRY is required, e.g. make push REGISTRY=docker.io/<user> TAG=latest)
endif
	docker buildx build \
	  --platform $(PLATFORM) \
	  --file docker/Dockerfile \
	  --tag $(IMAGE_REF) \
	  --push \
	  .

.PHONY: check-files

# --- running ----------------------------------------------------------------

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

# --- bare metal -------------------------------------------------------------

install:
	./install.sh

start:
	./start.sh

# --- cleanup ----------------------------------------------------------------

clean:
	-$(COMPOSE) down -v
	-docker image rm $(IMAGE_REF)

distclean: clean
	rm -rf local

# --- why there is no arm64 image -------------------------------------------
#
# Every binary in the stack is 32-bit x86 and nothing else exists upstream:
# engine_i486.so (ReHLDS), cs.so (ReGameDLL), metamod_i386.so, reunion_mm_i386.so,
# amxmodx_mm_i386.so, reapi_amxx_i386.so. Building for arm64 would only change
# the base image — buildx does not recompile anything — so the payload would run
# through QEMU, and Valve's Steam init segfaults there. Rosetta is no help
# either: it emulates x86_64 only, never 32-bit x86.
