#!/bin/bash
set -euxo pipefail
# Set variables first
REPO_NAME='db-mcp-server'
# Base image refs — CI populates these from probed GHCR mirrors
# (ghcr.io/mekayelanik/base-images/...) when available, else falls back
# to Docker Hub short refs. Local builds read the committed defaults.
GO_IMAGE=$(cat ./build_data/base-image 2>/dev/null       || echo "golang:alpine")
HAPROXY_IMAGE=$(cat ./build_data/haproxy-image 2>/dev/null || echo "haproxy:lts-alpine")
XX_IMAGE=$(cat ./build_data/xx-image 2>/dev/null          || echo "tonistiigi/xx:1.9.0")
RUNTIME_IMAGE=$(cat ./build_data/runtime-image 2>/dev/null || echo "alpine:latest")
DB_MCP_VERSION=$(cat ./build_data/version 2>/dev/null || exit 1)
# mcp-proxy: stdio<->StreamableHTTP/SSE bridge. Replaces supergateway.
# Stateful by default (one stdio child shared across all sessions) - avoids
# the spawn-per-request memory leak that affected supergateway in stateless
# mode (supercorp-ai/supergateway#108).
MCP_PROXY_PKG=$(cat ./build_data/mcp_proxy_version 2>/dev/null || echo "mcp-proxy")
DOCKERFILE_NAME="Dockerfile.$REPO_NAME"

# Create a temporary file safely
TEMP_FILE=$(mktemp "${DOCKERFILE_NAME}.XXXXXX") || {
    echo "Error creating temporary file" >&2
    exit 1
}

# Check if this is a publication build
if [ -e ./build_data/publication ]; then
    # For publication builds, create a minimal Dockerfile that just tags the existing image
    {
        echo "ARG GO_IMAGE=$GO_IMAGE"
        echo "ARG DB_MCP_VERSION=$DB_MCP_VERSION"
        echo "FROM $RUNTIME_IMAGE"
    } > "$TEMP_FILE"
else
    # Write the Dockerfile content to the temporary file first
    {
        echo "ARG GO_IMAGE=$GO_IMAGE"
        echo "ARG DB_MCP_VERSION=$DB_MCP_VERSION"
        cat << EOF
# syntax=docker/dockerfile:1
# =============================================================================
# db-mcp-server — Multi-stage Dockerfile
# Supports: linux/amd64, linux/arm64, linux/arm/v7
# =============================================================================

# ── xx cross-compilation helpers ──────────────────────────────────────────────
FROM --platform=\$BUILDPLATFORM $XX_IMAGE AS xx

# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM --platform=\$BUILDPLATFORM $GO_IMAGE AS builder

# Author info:
LABEL org.opencontainers.image.authors="MOHAMMAD MEKAYEL ANIK <mekayel.anik@gmail.com>"
LABEL org.opencontainers.image.source="https://github.com/mekayelanik/db-mcp-server-docker"

# Copy xx tools into the builder
COPY --from=xx / /

# Install host build tools
RUN apk add --no-cache make clang lld

# Install target-platform C toolchain via xx
ARG TARGETPLATFORM
RUN xx-apk add --no-cache musl-dev gcc

WORKDIR /app

# Copy full source before \`go mod download\` so go.mod \`replace\` directives
# pointing to in-tree paths (e.g. ./hack/mcp-go in v1.4.x) can resolve.
# Trades the dep-layer caching benefit for correctness across every release
# tag — buildx layer cache (cache-ref) still hits when source is unchanged.
COPY . .
RUN go mod download

# xx-go sets GOOS, GOARCH, GOARM, CC, and CGO_ENABLED=1 automatically.
RUN --mount=type=cache,target=/root/.cache/go-build \\
    --mount=type=cache,target=/go/pkg/mod \\
    CGO_ENABLED=1 xx-go build \\
    -trimpath \\
    -ldflags="-s -w" \\
    -o ./bin/server \\
    cmd/server/main.go \\
  && xx-verify ./bin/server

# ── HAProxy with native QUIC/H3 support ─────────────────────────────────────
FROM $HAPROXY_IMAGE AS haproxy-src

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM $RUNTIME_IMAGE

RUN apk add --no-cache \\
    ca-certificates \\
    tzdata \\
    bash \\
    haproxy \\
    openssl \\
    netcat-openbsd \\
    bind-tools \\
    iputils \\
    busybox-extras \\
    curl \\
    python3 \\
    py3-pip

# Replace Alpine HAProxy with official build (native QUIC/H3 support)
COPY --from=haproxy-src /usr/local/sbin/haproxy /usr/sbin/haproxy
RUN mkdir -p /usr/local/sbin && ln -sf /usr/sbin/haproxy /usr/local/sbin/haproxy

# Install mcp-proxy (replaces supergateway). Pure-Python via pip.
RUN --mount=type=cache,target=/root/.cache/pip \\
    echo "Installing ${MCP_PROXY_PKG}..." && \\
    pip install --no-cache-dir --break-system-packages ${MCP_PROXY_PKG} && \\
    mcp-proxy --version || true && \\
    rm -rf /tmp/* /var/tmp/*

WORKDIR /app

COPY --from=builder /app/bin/server /app/server
COPY config.json /app/config.json
COPY ./resources/ /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/banner.sh /usr/local/bin/healthcheck.sh \\
    && if [ -f /usr/local/bin/build-timestamp.txt ]; then chmod +r /usr/local/bin/build-timestamp.txt; fi \\
    && mkdir -p /etc/haproxy \\
    && mv -vf /usr/local/bin/haproxy.cfg.template /etc/haproxy/haproxy.cfg.template \\
    && mkdir -p /app/data /app/logs

LABEL org.opencontainers.image.description="db-mcp-server (mcp-proxy stdio<->HTTP bridge)"

ENV SERVER_PORT=9092
ENV INTERNAL_SERVER_PORT=38011
ENV TRANSPORT_MODE=stdio
ENV PROTOCOL=SHTTP
ENV MCP_PROXY_STATELESS=false
ENV DB_MCP_MAX_MEM_MB=4096
ENV HAPROXY_FRONTEND_MAXCONN=64
ENV HAPROXY_SERVER_MAXCONN=16
ENV CONFIG_PATH=/app/config.json
ENV API_KEY=
ENV CORS=
ENV ENABLE_HTTPS=true
ENV TLS_CERT_PATH=/etc/haproxy/certs/server.crt
ENV TLS_KEY_PATH=/etc/haproxy/certs/server.key
ENV TLS_PEM_PATH=/etc/haproxy/certs/server.pem
ENV TLS_CN=localhost
ENV TLS_SAN=DNS:localhost
ENV TLS_DAYS=365
ENV TLS_MIN_VERSION=TLSv1.3
ENV HTTP_VERSION_MODE=auto
ENV PUID=1000
ENV PGID=1000

EXPOSE 9092
EXPOSE 9092/udp
VOLUME ["/app/logs"]

# L7 health check: HAProxy answers /healthz locally
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \\
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

EOF
    } > "$TEMP_FILE"
fi

# Atomically replace the target file with the temporary file
if mv -f "$TEMP_FILE" "$DOCKERFILE_NAME"; then
    echo "Dockerfile for $REPO_NAME created successfully."
else
    echo "Error: Failed to create Dockerfile for $REPO_NAME" >&2
    rm -f "$TEMP_FILE"
    exit 1
fi
