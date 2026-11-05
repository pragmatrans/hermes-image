# hermes-image

A pin of the Hermes Agent runtime we actually run, kept in our own registry so a bad upstream
update cannot take the working version away from us.

`FROM nousresearch/hermes-agent@sha256:e6d81ae5…` (the exact multi-arch image currently deployed)
plus `gh` and `jq`, which otherwise have to be installed by hand inside the container after every
migration. Config is **not** in here: `/opt/data` is a volume and config lives in git snapshots
([`hermes-config`](https://github.com/pragmatrans/hermes-config), script `scripts/zriz.sh`).

## Contents

| | |
|---|---|
| base | `nousresearch/hermes-agent:v0.22.7@sha256:e6d81ae52ebf6a43efa529701405509f20054ba818f179ddd748bed4f8af584c` |
| platforms | `linux/amd64`, `linux/arm64` |
| added | `gh 2.102.0`, `jq 1.7.1` |
| not included | `.env`, `auth.json`, `config.yaml`, sessions — all of that is volume state |

## Use

```bash
docker pull ghcr.io/pragmatrans/hermes-image:v0.22.7
docker tag  ghcr.io/pragmatrans/hermes-image:v0.22.7 nousresearch/hermes-agent:local-v0.22.7
```

Point `image:` in `docker-compose.yml` at `nousresearch/hermes-agent:local-v0.22.7`, then
`docker compose up -d`. Tags published per build: `v<version>`, `v<version>-<YYYYMMDD>`, `latest`.

## Mirroring a new version

1. Upgrade Hermes the usual way and confirm it actually works.
2. Read the digest of that tag:

   ```bash
   curl -s https://hub.docker.com/v2/repositories/nousresearch/hermes-agent/tags/v0.23.0 \
     | jq -r .digest
   ```

3. Actions → **build** → *Run workflow*, set `base` to
   `nousresearch/hermes-agent:v0.23.0@sha256:<digest>`.
4. The resulting `v0.23.0` tag is the new known-good runtime slice.

## Why public

Public repos get unlimited Actions minutes and public GHCR packages get free storage and
transfer; private GHCR is capped at 500 MB while this image is ~1 GB. Nothing secret is inside —
the inheriting `.env`, `auth.json` and config stay on the volume.
