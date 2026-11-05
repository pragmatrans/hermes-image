# Дзеркало робочої версії Hermes у нашому власному GHCR + те, що ми ставили руками.
#
# Навіщо: базовий образ пінить digest, тобто це той самий біт-у-біт Hermes, який зараз
# працює в нас. Якщо апстрім оновить latest і щось зламає — тягнемо свій тег v0.22.7
# і повертаємось до робочого стану. Плюс gh і jq всередині, щоб не ставити їх у
# контейнер після кожного переїзду.
#
# Конфігу тут НЕМА і не буде: /opt/data — це volume, конфіг живе в git-зрізах
# (scripts/zriz.sh), а не в шарах образу.
ARG BASE=nousresearch/hermes-agent:v0.22.7@sha256:e6d81ae52ebf6a43efa529701405509f20054ba818f179ddd748bed4f8af584c
FROM ${BASE}

USER root

ARG GH_VERSION=2.102.0
ARG JQ_VERSION=1.7.1

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
