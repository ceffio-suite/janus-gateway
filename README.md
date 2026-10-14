<p align="center">
  <img src="assets/ceffio-banner-1280.png" alt="Ceffio" width="100%">
</p>

<p align="center">
  <a href="https://github.com/ceffio-suite/janus-gateway/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/ceffio-suite/janus-gateway/build.yml?branch=main&label=build&logo=github" alt="build status"></a>
  <a href="https://github.com/ceffio-suite/janus-gateway/pkgs/container/janus-gateway"><img src="https://img.shields.io/badge/GHCR-janus--gateway-2496ED?logo=docker&logoColor=white" alt="GHCR image"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0--or--later-blue" alt="AGPL-3.0-or-later license"></a>
</p>

# janus-gateway — Janus image for Ceffio

Image of the **Janus SFU** used by the *High Performance Backend* of Nextcloud
Talk in [Ceffio](https://github.com/ceffio-suite/ceffio).

## Why this repository

Talk's backend (Strukturag's signaling server) relies on **Janus** to carry the
WebRTC media. The official compose ships a `Dockerfile`, but it is meant for a
local `docker compose build:` — and a k3s cluster has no build toolchain.

This repository therefore produces a **published image**, with two guarantees:

- **reproducibility**: every version is pinned (usrsctp by commit, libsrtp and
  Janus by tag). Nothing points at `master`.
- **Ceffio configuration**: reduced media range and NAT handling, described
  below.

## Image

    ghcr.io/ceffio-suite/janus-gateway:1.4.3-1

Targets `linux/amd64` (the Ceffio VM is x86_64).

## What the configuration changes compared to stock Janus

### 1. Reduced media range: `20000-20100`

Janus listens on `20000-40000` by default, that is **20,001 UDP ports** to open
on the firewall. For a small team, that is needlessly wide: each participant
consumes 1 to 2 ports, so 100 ports cover dozens of simultaneous participants.

Reducing the range also reduces the **exposed surface** — a point that matters
when the server is on the Internet.

### 2. NAT: the public IP is injected at startup, never hard-coded

Behind the firewall, Janus must announce an address that browsers can actually
reach. If it announces its private addresses in the ICE candidates, the media
**never gets through** — the classic self-hosted WebRTC trap.

The public IP is therefore passed via an environment variable at startup:

    JANUS_PUBLIC_IP=<deployment-public-ip>

**It is never written in this repository** — not in a file, not in an example,
not in a test. A public address is reconnaissance information: it reveals the
existence and the location of an infrastructure. The deployer provides it, the
repository does not know it.

> **Already handled:** if `JANUS_STUN_SERVER` is set, Janus discovers its own
> public address via STUN at startup (outgoing UDP packet, no extra port to
> open) and `JANUS_PUBLIC_IP` becomes unnecessary. See the "Automatic
> detection" section below.

### 3. Self-signed DTLS certificate, generated at startup

WebRTC requires a certificate for the DTLS handshake. A self-signed certificate
is **normal and accepted** by browsers in this context — unlike the TLS of a
website, which requires a recognized authority. It is generated on first
startup if it does not exist.

## Environment variables

| Variable | Default | Role |
|---|---|---|
| `JANUS_PUBLIC_IP` | *(empty)* | Announced public IP (1:1 NAT). Empty = no mapping. |
| `JANUS_RTP_PORT_RANGE` | `20000-20100` | UDP range for media. |
| `JANUS_DEBUG_LEVEL` | `4` | Janus log level (0-7). |
| `JANUS_STUN_SERVER` | *(empty)* | Optional STUN server. |

## Ports

    TCP 8088     Janus HTTP API (used by the signaling server)
    TCP 8188     Janus WebSocket transport
    UDP 20000-20100  RTP media

The media port is **configurable** — it must match the firewall's NAT rule.
Ceffio opens it as `20000-20100/udp` towards VM 310.

## Build locally

    docker buildx build --platform linux/amd64 -t janus-gateway:local .

Compiling from source (usrsctp, libsrtp, Janus): allow about **ten minutes**
cold, far less with cache.

## Publish a new version

    git tag v1.4.3-1 && git push origin v1.4.3-1

The workflow then publishes `ghcr.io/ceffio-suite/janus-gateway:1.4.3-1`.
Ceffio pins this tag in its version registry — **never `latest`**: a tag that
moves makes a deployment non-reproducible.

## Updating Janus

1. change `JANUS_VERSION` in the `Dockerfile` (and the corresponding tag);
2. if the new version adds or renames configuration keys, **regenerate the
   `janus*.jcfg` files from the `conf/` directory of the upstream tag** — never
   edit them blindly;
3. rebuild, test, then publish a new tag.

## License

This repository is licensed **AGPL-3.0-or-later**, Copyright © MANDEM — the
same license as the [Ceffio suite](https://github.com/ceffio-suite/ceffio) it
serves. (An Apache-2.0 placeholder was committed before the suite-wide AGPL
decision; this replaces it.)

What that covers, file by file:

| Content | License | Why |
|---|---|---|
| `Dockerfile`, `docker-entrypoint.sh`, `.github/workflows/` | AGPL-3.0-or-later | Written by MANDEM; a build recipe and runtime script are not derivative works of Janus |
| `janus*.jcfg` | GPL-3.0 (remain GPL, combined into this repo under AGPL-3.0 §13) | Derived from the `conf/*.jcfg.sample` files of the upstream GPL-3.0 Janus repository — verified by line-for-line comparison; Ceffio's adaptations stay under the upstream license |
| Janus binary compiled into the image | GPL-3.0 | [meetecho/janus-gateway](https://github.com/meetecho/janus-gateway), fetched from the official tarball at build time |
| usrsctp / libsrtp compiled into the image | BSD-3-Clause | [sctplab/usrsctp](https://github.com/sctplab/usrsctp), [cisco/libsrtp](https://github.com/cisco/libsrtp) |

AGPL-3.0 §13 expressly permits combining GPL-3.0 covered works with AGPL
works, so the repository, the image and the Ceffio suite are coherent: GPL
config + AGPL scripts + GPL Janus binary, no relicensing of upstream code.