# syntax=docker/dockerfile:1
# =============================================================================
# db-mcp-server — Multi-stage Dockerfile
# Supports: linux/amd64, linux/arm64, linux/arm/v7
#
# Uses tonistiigi/xx for CGO cross-compilation and BUILDPLATFORM pinning
# so the Go toolchain always runs natively (no QEMU slowdown on the builder).
# =============================================================================

# ── xx cross-compilation helpers ──────────────────────────────────────────────
FROM --platform=$BUILDPLATFORM tonistiigi/xx:1.9.0 AS xx

# ── Stage 1: Builder ──────────────────────────────────────────────────────────
# Always runs on the native build platform (amd64 in CI), cross-compiles output
FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS builder

# Copy xx tools into the builder
COPY --from=xx / /

# Install host build tools
RUN apk add --no-cache make clang lld

# Install target-platform C toolchain via xx (musl-dev + gcc for TARGETPLATFORM)
ARG TARGETPLATFORM
RUN xx-apk add --no-cache musl-dev gcc

WORKDIR /app

# Cache dependency layer separately from source
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# xx-go sets GOOS, GOARCH, GOARM, CC, and CGO_ENABLED=1 automatically.
# -trimpath and -s -w reduce binary size.
RUN CGO_ENABLED=1 xx-go build \
    -trimpath \
    -ldflags="-s -w" \
    -o ./bin/server \
    cmd/server/main.go \
  && xx-verify ./bin/server

# ── HAProxy with native QUIC/H3 support ─────────────────────────────────────
# HAPROXY_IMAGE is injected by the CI pipeline (sed replacement before build).
# Default: haproxy:lts-alpine (used for local builds without CI).
FROM haproxy:lts-alpine AS haproxy-src

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM alpine:latest

RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    bash \
    haproxy \
  openssl \
    netcat-openbsd \
    bind-tools \
    iputils \
    busybox-extras

# Replace Alpine HAProxy with official build (native QUIC/H3 support)
COPY --from=haproxy-src /usr/local/sbin/haproxy /usr/sbin/haproxy
RUN mkdir -p /usr/local/sbin && ln -sf /usr/sbin/haproxy /usr/local/sbin/haproxy

WORKDIR /app

COPY --from=builder /app/bin/server /app/server
COPY config.json /app/config.json
COPY haproxy.cfg.template /etc/haproxy/haproxy.cfg.template
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN mkdir -p /app/data /app/logs \
  && chmod +x /usr/local/bin/docker-entrypoint.sh

ENV SERVER_PORT=9092
ENV INTERNAL_SERVER_PORT=38011
ENV TRANSPORT_MODE=sse
ENV CONFIG_PATH=/app/config.json
ENV API_KEY=
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

# L7 health check: auto-detects HTTP/HTTPS via ENABLE_HTTPS env var
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD sh -c 'wget -q --spider --no-check-certificate $([ "$ENABLE_HTTPS" = "true" ] && echo https || echo http)://localhost:${SERVER_PORT:-9092}/healthz'

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
