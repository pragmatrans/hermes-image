# Mirror of the Hermes runtime we actually run, plus the tools we kept installing by hand.
#
# Labels + /etc/hermes-tools.txt: щоб «що змінилось між двома тегами» було diff-ом, а не
# археологією. base — пінений дайджест, решта — інвентар, знятий під час збірки.
#
# Why: the base image is pinned by digest, so this is the exact Hermes currently
# deployed. If upstream moves latest and breaks something, we pull our own v0.22.7
# and get back to a working state.
#
# Scope rule: code + tools in layers, state in the volume. Config, skills, plugins,
# cron and sessions live in /opt/data (git-snapshotted, synced between the two
# brothers) and must never be baked here — they change daily, and a layer would
# silently drift from the Mac side. Secrets never go into any layer, not even base64.
#
# No config here on purpose: /opt/data is a volume and config lives in git snapshots
# (scripts/zriz.sh), not in image layers.
ARG BASE=nousresearch/hermes-agent:v0.23.2@sha256:d6746a084e9341baada483e3d6210444d3c1aeb7c130f0915150065fb2851459
FROM ${BASE}

USER root

ARG BASE
ARG GH_VERSION=2.102.0
ARG JQ_VERSION=1.7.1
ARG BUILD_TAG=dev

# gh + jq: installed by hand after every migration before this image existed.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSL -o /usr/local/bin/jq \
        "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${arch}"; \
    chmod 0755 /usr/local/bin/jq; \
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${arch}.tar.gz" \
        | tar -xz -C /tmp; \
    install -m 0755 "/tmp/gh_${GH_VERSION}_linux_${arch}/bin/gh" /usr/local/bin/gh; \
    rm -rf "/tmp/gh_${GH_VERSION}_linux_${arch}"; \
    gh --version; jq --version

# Tool layer: each of these was a manual install inside a live container at least once.
#   pyyaml        — our scripts parse config.yaml; neither the venv python nor the
#                   distro one had a yaml module (we hit that twice in one week).
#   poppler-utils — pdftotext for reading PDFs without a Python stack
#   zbar-tools    — zbarimg: we verify QR codes we generate (WireGuard profile)
#   qrencode      — generate QR codes (same WireGuard case)
#   git-lfs       — Asuswrt-Merlin trees and vendor blobs use LFS
#   sqlite3       — ad-hoc inspection of state.db without writing a Python one-liner
# pyyaml: `python3` in this image IS /opt/hermes/.venv/bin/python3, and that venv ships
# without pip (created by uv). So: system python3-yaml for the distro interpreter, then
# bootstrap pip into the venv (get-pip) and install the cp314 wheel there — installing
# into Debian's dist-packages would be invisible to the venv Python.
RUN set -eux; \
    apt-get -o Acquire::Retries=3 update; \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
        poppler-utils zbar-tools qrencode git-lfs sqlite3 python3-yaml \
        unzip p7zip-full netcat-openbsd rsync file patch \
        iproute2 bind9-dnsutils whois traceroute mtr-tiny lsof socat zip zstd xz-utils \
        binutils adb libopus0 libsodium23 aria2 wget; \
    rm -rf /var/lib/apt/lists/*; \
    /opt/hermes/.venv/bin/python -m ensurepip --default-pip >/dev/null 2>&1 || true; \
    if ! /opt/hermes/.venv/bin/python -m pip --version >/dev/null 2>&1; then \
        curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py; \
        /opt/hermes/.venv/bin/python /tmp/get-pip.py --no-cache-dir; \
        rm -f /tmp/get-pip.py; \
    fi; \
    /opt/hermes/.venv/bin/python -m pip install --no-cache-dir pyyaml

# sqlite3 CLI needs a shim: Debian's binary is built against libsqlite3 3.46, but the base image
# carries a newer libsqlite3 (3.53, built for Python) in /usr/local/lib, which the loader picks
# first — the CLI then dies with "SQLite header and source version mismatch" and exits non-zero
# WITHOUT running the query (so `sqlite3 --version` alone proves nothing). Pin the CLI to the
# distro lib in a wrapper; the venv Python keeps its newer lib untouched.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) LIBDIR=/usr/lib/x86_64-linux-gnu ;; \
        arm64) LIBDIR=/usr/lib/aarch64-linux-gnu ;; \
        *) echo "unknown arch $(dpkg --print-architecture)"; exit 1 ;; \
    esac; \
    printf '#!/bin/sh\n# див. коментар у Dockerfile: системна libsqlite3, інакше CLI падає з mismatch\nexec env LD_LIBRARY_PATH=%s /usr/bin/sqlite3 "$@"\n' "$LIBDIR" > /usr/local/bin/sqlite3; \
    chmod 0755 /usr/local/bin/sqlite3; \
    sqlite3 :memory: 'select 42' | grep -qx 42

# Self-check: a tool layer that silently misses a binary is worse than no layer,
# because the next session finds out halfway through a task.
# sqlite3 перевіряємо РЕАЛЬНИМ запитом: --version мовчить, коли ABI бібліотеки не той.
RUN set -eux; \
    for b in pdftotext zbarimg qrencode git-lfs sqlite3 gh jq \
             unzip 7z nc rsync file patch \
             ip ss dig whois traceroute mtr lsof socat zip zstd xz strings adb aria2c wget; do \
        command -v "$b" >/dev/null || { echo "MISSING: $b"; exit 1; }; \
    done; \
    python3 -c 'import yaml; print("pyyaml", yaml.__version__)'; \
    sqlite3 :memory: 'select 42' | grep -qx 42; \
    git lfs version; pdftotext -v 2>&1 | head -1 || true; \
    unzip -v | head -1; 7z | head -3 | tail -1; nc -h 2>&1 | head -1 || true; \
    python3 -c 'import ctypes; ctypes.CDLL("libopus.so.0"); ctypes.CDLL("libsodium.so.23"); print("opus+sodium ok")'; \
    aria2c --version | head -1; wget --version | head -1

# pnpm: у 0.23 `hermes pm` вважає його обовʼязковим для збирання JS-артефактів (Web UI, плагіни).
# Без нього кожна команда друкує «install out of sync (pnpm: not installed or outdated)».
RUN set -eux; \
    npm install -g pnpm@10 >/dev/null; \
    pnpm --version

# Патч cron/jobs.py БІЛЬШЕ НЕ ПОТРІБЕН (перевірено 20.11 на 0.23.2).
# У 0.23 запис jobs.json атомарний: mkstemp_beside → fsync → os.replace, тому читач не бачить
# порожнього файла. Наш retry захищав від гонки, яку давав virtiofs (cron тепер на ext4-томі).
# Замість патчу — нагляд: cron-audit (кожні 30 хв) повідомляє, якщо jobs.json не читається.
# Старий патч лежить у patches/attic/ — на випадок повернення на 0.22.x.

# Inventory layer: what exactly is inside, in a form you can diff between two tags.
LABEL org.opencontainers.image.title="hermes-image" \
      org.opencontainers.image.description="Hermes Agent runtime (pinned base) plus ops tools" \
      org.opencontainers.image.source="https://github.com/pragmatrans/hermes-image" \
      org.opencontainers.image.version="${BUILD_TAG}" \
      org.opencontainers.image.base.name="${BASE}" \
      com.pragmatrans.hermes.base="${BASE}" \
      com.pragmatrans.hermes.build-tag="${BUILD_TAG}"

RUN set -eux; \
    { \
      echo "# base: ${BASE}"; \
      echo "# build tag: ${BUILD_TAG}"; \
      echo; \
      echo "== dpkg (ops tools) =="; \
      dpkg-query -W -f='${Package} ${Version}\n' \
          poppler-utils zbar-tools qrencode git-lfs sqlite3 python3-yaml unzip p7zip-full \
          netcat-openbsd rsync file patch iproute2 bind9-dnsutils whois traceroute mtr-tiny \
          lsof socat zip zstd xz-utils binutils adb libopus0 libsodium23 aria2 wget \
          2>/dev/null || true; \
      echo; \
      echo "== python venv =="; \
      /opt/hermes/.venv/bin/python -m pip freeze 2>/dev/null | sort || true; \
      echo; \
      echo "== local patches =="; \
      echo "0001-cron-jobs-parse-retry: applied to cron/jobs.py (transient-read retry)"; \
      echo; \
      echo "== hermes =="; \
      /opt/hermes/bin/hermes --version 2>/dev/null || true; \
    } > /etc/hermes-tools.txt; \
    test -s /etc/hermes-tools.txt; \
    grep -q '== dpkg' /etc/hermes-tools.txt