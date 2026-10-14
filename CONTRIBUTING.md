# Contributing to janus-gateway

This repository publishes one thing: a **reproducible Janus WebRTC gateway
image** for Nextcloud Talk's High Performance Backend, as deployed by
[Ceffio](https://github.com/ceffio-suite/ceffio).

## GitFlow

| Branch | Role |
|---|---|
| `main` | every commit is a releasable state |
| `develop` | integration branch |
| `feature/<name>` | one change, merged into `develop` by PR |
| `release/x.y.z` | stabilisation from `develop`, tagged from here |
| `hotfix/x.y.z` | fix from `main`, merged back into both |

Work arrives by pull request into `develop`; `main` receives merges from
`release/*` and `hotfix/*` branches. PR titles follow
[Conventional Commits](https://www.conventionalcommits.org/) — they become the
release notes.

## Releasing

A release is a tag. Two workflows react to it, in order:

1. `build.yml` builds and pushes `ghcr.io/ceffio-suite/janus-gateway:<version>`;
2. `release.yml` waits for that build to be green, **pulls the image
   anonymously to prove it is public and pullable**, then creates the GitHub
   Release with generated notes.

```bash
git checkout develop && git pull
git checkout -b release/1.4.0
git tag -a v1.4.0 -m "janus-gateway 1.4.0"
git push origin release/1.4.0 && git push origin v1.4.0
# after both workflows are green:
git checkout main && git merge --no-ff release/1.4.0 && git push
git checkout develop && git merge --no-ff release/1.4.0 && git push
```

## The rules of this repository

1. **Everything upstream is pinned.** usrsctp by commit, libsrtp and Janus by
   tag. Nothing may point at `master` or `latest`: an image whose inputs can
   drift cannot be reproduced, and a media gateway that cannot be reproduced
   cannot be debugged six months later.
2. **The image tag equals the Git tag.** An image without a version can be
   neither compared nor rolled back.
3. **No infrastructure identifiers in this repository.** No real public IP,
   real domain or account name — `1.2.3.4` in `janus.jcfg` is a deliberate
   placeholder. The public address is injected at runtime via
   `JANUS_PUBLIC_IP`, discovered by STUN; it is never written here.
4. **The media range stays `20000-20100`.** It is deliberately narrower than
   stock Janus (20000-40000) and coordinated with the firewall documentation
   in the Ceffio README. Changing it is a cross-repository change.
5. **A release that was not pullable was not released.** `release.yml`
   performs the anonymous pull; do not remove that step to make a pipeline
   pass — fix the package visibility instead.

## Verifying a change locally

```bash
docker build --platform linux/amd64 -t janus-gateway:test .
docker run --rm -e JANUS_DEBUG_LEVEL=4 janus-gateway:test
# the log must show the gateway starting and the videoroom plugin loading
```

## License

AGPL-3.0-or-later, Copyright © MANDEM — see [LICENSE](LICENSE) and the
License section of the README. By contributing you accept that your
contribution is licensed the same way. The Janus software built by this image
is GPL-3.0 (upstream), and the `janus*.jcfg` configuration files derive from
its GPL-3.0 samples — they remain under GPL-3.0, combined here under AGPL-3.0
§13.
