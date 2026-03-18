# syntax=docker/dockerfile:1
# =============================================================================
# db-mcp-server — Multi-stage Dockerfile
# Supports: linux/amd64, linux/arm64, linux/arm/v7
#
# Uses tonistiigi/xx for CGO cross-compilation and BUILDPLATFORM pinning
# so the Go toolchain always runs natively (no QEMU slowdown on the builder).
# =============================================================================

# ── xx cross-compilation helpers ──────────────────────────────────────────────
FROM --platform=$BUILDPLATFORM tonistiigi/xx:1.6.1 AS xx

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

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM alpine:latest

RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    bash \
    nodejs-current \
    npm \
    netcat-openbsd \
    bind-tools \
    iputils \
    busybox-extras

WORKDIR /app

COPY --from=builder /app/bin/server /app/server
COPY config.json /app/config.json

RUN mkdir -p /app/data /app/logs

ENV SERVER_PORT=9092
ENV TRANSPORT_MODE=sse
ENV CONFIG_PATH=/app/config.json

EXPOSE 9092
VOLUME ["/app/logs"]

CMD ["/bin/bash", "-c", "/app/server -t ${TRANSPORT_MODE} -p ${SERVER_PORT} -c ${CONFIG_PATH}"]
