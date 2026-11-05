# hermes-image

Наше дзеркало робочої версії Hermes Agent у GHCR: базовий образ піниться digest-ом,
тобто це той самий Hermes, який зараз працює. Якщо апстрім оновить `latest` і щось
зламає — тягнемо свій тег і повертаємось до робочого стану.

Зверху докладені `gh` та `jq` (те, що інакше треба ставити руками в контейнер після
кожного переїзду). Конфігу в образі немає: `/opt/data` — volume, конфіг живе в
git-зрізах (`hermes-config`, скрипт `scripts/zriz.sh`).

## Що в образі

| | |
|---|---|
| база | `nousresearch/hermes-agent:v0.22.7@sha256:e6d81ae5…` (arm64 + amd64) |
| додано | `gh 2.102.0`, `jq 1.7.1` |
| не входить | `.env`, `auth.json`, `config.yaml`, сесії — все це на volume |

## Забрати

```bash
docker pull ghcr.io/pragmatrans/hermes-image:v0.22.7
docker tag ghcr.io/pragmatrans/hermes-image:v0.22.7 nousresearch/hermes-agent:local-v0.22.7
```

Підміна в `docker-compose.yml` — рядок `image:` на свій, далі `docker compose up -d`.

## Нова версія

1. Оновити Hermes звичайним способом, перевірити, що все живе.
2. Дізнатись digest нової версії:
   ```bash
   curl -s https://hub.docker.com/v2/repositories/nousresearch/hermes-agent/tags/v0.23.0 \
     | jq -r .digest
   ```
3. Actions → build → Run workflow, у полі `base`:
   `nousresearch/hermes-agent:v0.23.0@sha256:<digest>`.
4. Отриманий тег `v0.23.0` — це і є новий «робочий зріз» образу.

## Межі безкоштовного плану

Репозиторій публічний і образ публічний — Actions-хвилини та сховище GHCR для
публічних пакетів безкоштовні без ліміту. Приватні пакети мали б 500 МБ, а цей
образ ~1 ГБ, тому публічність тут не косметика.
