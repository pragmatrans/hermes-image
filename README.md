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
| added | `gh 2.102.0`, `jq 1.7.1`, `pyyaml 6.0.3` (в venv), `pdftotext`, `zbarimg`, `qrencode`, `git-lfs`, `sqlite3` |
| not included | `.env`, `auth.json`, `config.yaml`, sessions — all of that is volume state |

## Why the tool layer is here

Every one of these was installed by hand inside a running container at least once, usually in the
middle of a task. The image installs them and then **checks itself** (build fails if a binary is
missing), and the `smoke` job runs the pushed image to prove the tools and the Hermes entrypoint both
work. What goes in layers: code and tools. What never does: config, skills, plugins, cron, sessions
(all of that is the `/opt/data` volume) and secrets.

## Tags: що означає кожен

| Тег | Що це | Для чого |
|---|---|---|
| `v0.22.7` | чиста база, без tool-шару | еталон «як у Nous», відкат |
| `v0.22.7-tools5` | tools4 + мережева діагностика (`ip`, `ss`, `dig`, `whois`, `traceroute`, `mtr`, `lsof`, `socat`), архіви (`zip`, `zstd`, `xz`), `strings`, `adb` | **ціль деплою** (4.79 ГБ, патч cron живий) |
| `v0.22.7-tools4` | unzip/p7zip/nc/rsync/file/patch + self-check | проміжний, не деплоїти (перекритий tools5) |
| `v0.22.7-tools3` | те саме + локальний патч `cron/jobs.py` (ретрай порожнього читання) | **зараз на маку**; відкат після tools5 |
| `v0.22.7-tools2` | база + tools, робочий sqlite3 | прибрати після підтвердження tools5 |
| `v0.22.7-tools2-<YYYYMMDD>` | те саме з датою | пін на конкретну збірку |
| ~~`latest`~~ | **більше не пушиться** | деплой тільки піненним тегом |

**`v0.22.7-tools` — ЗЛАМАНИЙ, не використовувати.** У ньому CLI `sqlite3` падав з
`SQLite header and source version mismatch` (Debian-бінарник зібраний під libsqlite3 3.46, а
базовий образ несе 3.53 у `/usr/local/lib`), і `sqlite3 --version` цього **не показував**.
Замінений на `-tools2`; **тег знято з реєстру 2026-11-16** (разом із датованим `-tools-20261116`).

## Що всередині: інвентар і мітки

При збірці створюється `/etc/hermes-tools.txt` — версії apt-тулів, `pip freeze` венва й
`hermes --version`, плюс рядок `# base: <digest>`. ОСІ-мітки несуть те саме (`org.opencontainers.image.base.name`,
`com.pragmatrans.hermes.build-tag`). Тому «що змінилось між тегами» — це `diff` двох файлів:

```bash
docker run --rm --entrypoint cat ghcr.io/pragmatrans/hermes-image:v0.22.7-tools3 /etc/hermes-tools.txt
```

Smoke-джоба ганяє образ на **обох** архітектурах (`linux/amd64` і `linux/arm64` під QEMU): раніше
arm64 не перевірявся взагалі, а саме на ньому працює мак.

## Use

```bash
docker pull ghcr.io/pragmatrans/hermes-image:v0.22.7-tools2
```

Point `image:` in `docker-compose.yml` **піненним** тегом (`…:v0.22.7-tools2`), then
`docker compose up -d`. Деплой — завжди піненним тегом: `latest` рухається сам і одного дня
принесе іншу базу.

> Історично мак тягнув локальний аліас `nousresearch/hermes-agent:local-<версія>` (так було в
> старому compose). 2026-11-16 мак перейшов на прямий тег реєстру; `local-v0.22.7` лишився
> на диску як відкат.

## Mirroring a new version

1. Upgrade Hermes the usual way and confirm it actually works.
2. Read the digest of that tag:

   ```bash
   curl -s https://hub.docker.com/v2/repositories/nousresearch/hermes-agent/tags/v0.23.0 \
     | jq -r .digest
   ```

3. Actions → **build** → *Run workflow*: set `base` to
   `nousresearch/hermes-agent:v0.23.0@sha256:<digest>` **і** `tag` явно (напр. `v0.23.0-tools`).
   Пуш у `main` білд більше не запускає — з порожнім `tag` він обчислював `v<база>` і затирав
   тег, на якому стоїть прод.
4. The resulting pinned tag is the new known-good runtime slice (`latest` рухається сам).

## Why public

Public repos get unlimited Actions minutes and public GHCR packages get free storage and
transfer; private GHCR is capped at 500 MB while this image is ~1 GB. Nothing secret is inside —
the inheriting `.env`, `auth.json` and config stay on the volume.
