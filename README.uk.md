# hermes-image

Пін того рантайму Hermes, який ми реально запускаємо — у нашому власному реєстрі, щоб погане
оновлення в апстрімі не забрало в нас робочу версію.

`FROM nousresearch/hermes-agent@sha256:e6d81ae5…` (той самий multi-arch образ, що зараз
розгорнутий) плюс `gh` і `jq`, які інакше доводиться ставити руками в контейнер після кожного
переїзду. Конфігу тут **немає**: `/opt/data` це volume, а конфіг живе в git-зрізах
([`hermes-config`](https://github.com/pragmatrans/hermes-config), скрипт `scripts/zriz.sh`).

## Що в образі

| | |
|---|---|
| база | `nousresearch/hermes-agent:v0.22.7@sha256:e6d81ae52ebf6a43efa529701405509f20054ba818f179ddd748bed4f8af584c` |
| платформи | `linux/amd64`, `linux/arm64` |
| докладено | `gh 2.102.0`, `jq 1.7.1` |
| не входить | `.env`, `auth.json`, `config.yaml`, сесії — усе це стан на volume |

## Як користуватись

```bash
docker pull ghcr.io/pragmatrans/hermes-image:v0.22.7
docker tag  ghcr.io/pragmatrans/hermes-image:v0.22.7 nousresearch/hermes-agent:local-v0.22.7
```

У `docker-compose.yml` поставити `image:` на `nousresearch/hermes-agent:local-v0.22.7`, далі
`docker compose up -d`. Теги на кожну збірку: `v<версія>`, `v<версія>-<YYYYMMDD>`, `latest`.

## Дзеркалити нову версію

1. Оновити Hermes звичайним способом і переконатись, що справді працює.
2. Взяти digest цього тега:

   ```bash
   curl -s https://hub.docker.com/v2/repositories/nousresearch/hermes-agent/tags/v0.23.0 \
     | jq -r .digest
   ```

3. Actions → **build** → *Run workflow*, у полі `base` —
   `nousresearch/hermes-agent:v0.23.0@sha256:<digest>`.
4. Отриманий тег `v0.23.0` і є новий «робочий зріз» рантайму.

## Чому публічне

Публічні репо дають безліміт хвилин Actions, а публічні пакети GHCR — безкоштовне сховище й
трафік; приватний GHCR обмежений 500 МБ, тоді як цей образ ~1 ГБ. Секретів усередині немає:
`.env`, `auth.json` і конфіг лишаються на volume.
