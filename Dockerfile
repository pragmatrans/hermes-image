# Mirror of the Hermes runtime we actually run, plus the tools we kept installing by hand.
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
ARG BASE=nousresearch/hermes-agent:v0.22.7@sha256:e6d81ae52ebf6a43efa529701405509f20054ba818f179ddd748bed4f8af584c
FROM ${BASE}

USER root

ARG GH_VERSION=2.102.0
ARG JQ_VERSION=1.7.1

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
        poppler-utils zbar-tools qrencode git-lfs sqlite3 python3-yaml; \
    rm -rf /var/lib/apt/lists/*; \
    /opt/hermes/.venv/bin/python -m ensurepip --default-pip >/dev/null 2>&1 || true; \
    if ! /opt/hermes/.venv/bin/python -m pip --version >/dev/null 2>&1; then \
        curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py; \
        /opt/hermes/.venv/bin/python /tmp/get-pip.py --no-cache-dir; \
        rm -f /tmp/get-pip.py; \
    fi; \
    /opt/hermes/.venv/bin/python -m pip install --no-cache-dir pyyaml

# Self-check: a tool layer that silently misses a binary is worse than no layer,
# because the next session finds out halfway through a task.
RUN set -eux; \
    for b in pdftotext zbarimg qrencode git-lfs sqlite3 gh jq; do \
        command -v "$b" >/dev/null || { echo "MISSING: $b"; exit 1; }; \
    done; \
    python3 -c 'import yaml; print("pyyaml", yaml.__version__)'; \
    git lfs version; pdftotext -v 2>&1 | head -1 || true
