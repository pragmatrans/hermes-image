# Mirror of the Hermes runtime we actually run, plus the tools we used to install by hand.
#
# Why: the base image is pinned by digest, so this is the exact Hermes currently
# deployed. If upstream moves latest and breaks something, we pull our own v0.22.7
# and get back to a working state. gh and jq are baked in so they stop needing a
# hand install inside the container after every migration.
#
# No config here on purpose: /opt/data is a volume and config lives in git snapshots
# (scripts/zriz.sh), not in image layers.
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
