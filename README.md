<div align="center">

<img src="https://raw.githubusercontent.com/FreePeak/db-mcp-server/main/assets/logo.svg" alt="DB MCP Server Logo" width="300" />

# DB MCP Server — Docker Image

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Upstream License: MIT](https://img.shields.io/badge/Upstream_License-MIT-green.svg)](https://github.com/FreePeak/db-mcp-server/blob/main/LICENSE)
[![Upstream Repo](https://img.shields.io/badge/Upstream-FreePeak%2Fdb--mcp--server-orange?logo=github)](https://github.com/FreePeak/db-mcp-server)
[![Docker Pulls](https://img.shields.io/docker/pulls/mekayelanik/db-mcp-server?logo=docker&logoColor=white&label=Docker%20Pulls)](https://hub.docker.com/r/mekayelanik/db-mcp-server)
[![Docker Image Size](https://img.shields.io/docker/image-size/mekayelanik/db-mcp-server/latest?logo=docker&logoColor=white&label=Image%20Size)](https://hub.docker.com/r/mekayelanik/db-mcp-server)
[![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Fmekayelanik%2Fdb--mcp--server-blue?logo=github)](https://ghcr.io/mekayelanik/db-mcp-server)
[![Platforms](https://img.shields.io/badge/Platforms-amd64%20%7C%20arm64%20%7C%20arm%2Fv7-lightgrey?logo=linuxcontainers)](https://hub.docker.com/r/mekayelanik/db-mcp-server)
[![Go Version](https://img.shields.io/badge/Go-1.26-00ADD8?logo=go&logoColor=white)](https://go.dev)
[![Build Status](https://img.shields.io/github/actions/workflow/status/mekayelanik/db-mcp-server-docker/docker-publish.yml?branch=main&logo=githubactions&logoColor=white&label=Build)](https://github.com/mekayelanik/db-mcp-server-docker/actions/workflows/docker-publish.yml)
[![Last Commit](https://img.shields.io/github/last-commit/mekayelanik/db-mcp-server-docker?logo=github&logoColor=white)](https://github.com/mekayelanik/db-mcp-server-docker/commits/main)

<h3>Unofficial multi-arch Up-to-Date Docker image for <a href="https://github.com/FreePeak/db-mcp-server">FreePeak/db-mcp-server</a> — a powerful multi-database MCP server for AI assistants.</h3>

<div>
  <a href="#credits">Credits</a> •
  <a href="#images">Images</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#docker-cli">Docker CLI</a> •
  <a href="#docker-compose">Docker Compose</a> •
  <a href="#networking">Networking</a> •
  <a href="#security--transport">Security & Transport</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#supported-databases">Supported Databases</a> •
  <a href="#environment-variables">Environment Variables</a> •
  <a href="#license">License</a>
</div>

</div>

---

## Credits

This image packages the **[FreePeak/db-mcp-server](https://github.com/FreePeak/db-mcp-server)** project, built and maintained by [FreePeak](https://github.com/FreePeak) and contributors. All application code, functionality, and documentation originate from their repository and are licensed under the [MIT License](https://github.com/FreePeak/db-mcp-server/blob/main/LICENSE).

This repository only provides:
- A multi-arch Docker image (`linux/amd64`, `linux/arm64`, `linux/arm/v7`)
- GitHub Actions workflow for manual build/publish and promotion operations
- This Docker-focused usage documentation

For feature requests, bug reports, and source code contributions, please visit the [upstream repository](https://github.com/FreePeak/db-mcp-server).

---

## Images

Images are published to both registries via manual workflow dispatch (`Docker Build & Publish`) and are intended to remain identical in content.

Stable promotion is available through workflow actions:
- `auto-check` promotes to `stable` after 5 days of `latest` age (when eligible)
- `mark-stable` performs explicit/manual stable promotion

| Registry | Image |
|---|---|
| Docker Hub | `mekayelanik/db-mcp-server` |
| GHCR | `ghcr.io/mekayelanik/db-mcp-server` |

### Tags

| Tag | Description |
|---|---|
| `latest` | Latest manually published build from upstream `main` |
| `stable` | Promoted from a published version (auto-eligible after 5 days or manual `mark-stable`) |
| `YYYYMMDD-<sha>` | Immutable tag — exact upstream commit and build date, e.g. `20250312-19b7975` |
| `YYYYMMDD` | Floating date tag — latest build of that day |

### Platforms

| Platform | Architecture |
|---|---|
| `linux/amd64` | x86-64 (most servers, desktop Linux, WSL2) |
| `linux/arm64` | ARM 64-bit (Apple Silicon via Rosetta, AWS Graviton, Raspberry Pi 4/5) |
| `linux/arm/v7` | ARM 32-bit (Raspberry Pi 2/3, older ARM boards) |

---

## 😎 Buy Me a Coffee ☕︎

**Your support encourages me to keep creating/supporting my open-source projects.** If you found value in this project, you can buy me a coffee to keep me inspired.

<p align="center">
<a href="https://07mekayel07.gumroad.com/coffee" target="_blank">
<img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width="217" height="60">
</a>
</p>

## Quick Start

```bash
# Create a config file
cat > config.json <<'EOF'
{
  "connections": [
    {
      "id": "mydb",
      "type": "postgres",
      "host": "localhost",
      "port": 5432,
      "name": "mydb",
      "user": "myuser",
      "password": "mypassword"
    }
  ]
}
EOF

# Run
docker run -d \
  --name db-mcp-server \
  -p 9092:9092 \
  -v $(pwd)/config.json:/app/config.json \
  mekayelanik/db-mcp-server:latest
```

The MCP server is now available at `https://localhost:9092/sse` by default.

For local HTTP-only testing, set `ENABLE_HTTPS=false`.

---

## Docker CLI

### SSE Mode (default)

```bash
docker run -d \
  --name db-mcp-server \
  -p 9092:9092 \
  -v $(pwd)/config.json:/app/config.json \
  -e TRANSPORT_MODE=sse \
  -e SERVER_PORT=9092 \
  mekayelanik/db-mcp-server:latest
```

### Custom Port

```bash
docker run -d \
  --name db-mcp-server \
  -p 8080:8080 \
  -v $(pwd)/config.json:/app/config.json \
  -e SERVER_PORT=8080 \
  mekayelanik/db-mcp-server:latest
```

### STDIO Mode

```bash
docker run --rm -i \
  -v $(pwd)/config.json:/app/config.json \
  -e TRANSPORT_MODE=stdio \
  mekayelanik/db-mcp-server:latest
```

### Persistent Logs

```bash
docker run -d \
  --name db-mcp-server \
  -p 9092:9092 \
  -v $(pwd)/config.json:/app/config.json \
  -v $(pwd)/logs:/app/logs \
  mekayelanik/db-mcp-server:latest
```

### Pinned Immutable Tag (recommended for production)

```bash
docker run -d \
  --name db-mcp-server \
  -p 9092:9092 \
  -v $(pwd)/config.json:/app/config.json \
  mekayelanik/db-mcp-server:20250312-19b7975
```

### Pull from GHCR instead of Docker Hub

```bash
docker pull ghcr.io/mekayelanik/db-mcp-server:latest

docker run -d \
  --name db-mcp-server \
  -p 9092:9092 \
  -v $(pwd)/config.json:/app/config.json \
  ghcr.io/mekayelanik/db-mcp-server:latest
```

---

## Docker Compose

### Minimal — Single PostgreSQL

```yaml
services:
  db-mcp-server:
    image: mekayelanik/db-mcp-server:latest
    container_name: db-mcp-server
    restart: unless-stopped
    ports:
      - "9092:9092"
    volumes:
      - ./config.json:/app/config.json:ro
      - logs:/app/logs
    environment:
      TRANSPORT_MODE: sse
      SERVER_PORT: "9092"

volumes:
  logs:
```

---

### Full Stack — MCP Server + PostgreSQL + MySQL

```yaml
services:
  db-mcp-server:
    image: mekayelanik/db-mcp-server:latest
    container_name: db-mcp-server
    restart: unless-stopped
    ports:
      - "9092:9092"
    volumes:
      - ./config.json:/app/config.json:ro
      - logs:/app/logs
    environment:
      TRANSPORT_MODE: sse
      SERVER_PORT: "9092"
    depends_on:
      postgres:
        condition: service_healthy
      mysql:
        condition: service_healthy
    networks:
      - mcp-net

  postgres:
    image: postgres:16-alpine
    container_name: mcp-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: mydb
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myuser -d mydb"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - mcp-net

  mysql:
    image: mysql:8.0
    container_name: mcp-mysql
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: mydb
      MYSQL_USER: myuser
      MYSQL_PASSWORD: mypassword
      MYSQL_ROOT_PASSWORD: rootpassword
    volumes:
      - mysql-data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "myuser", "-pmypassword"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - mcp-net

volumes:
  postgres-data:
  mysql-data:
  logs:

networks:
  mcp-net:
    driver: bridge
```

`config.json` for the above stack:

```json
{
  "connections": [
    {
      "id": "postgres1",
      "type": "postgres",
      "host": "postgres",
      "port": 5432,
      "name": "mydb",
      "user": "myuser",
      "password": "mypassword"
    },
    {
      "id": "mysql1",
      "type": "mysql",
      "host": "mysql",
      "port": 3306,
      "name": "mydb",
      "user": "myuser",
      "password": "mypassword"
    }
  ]
}
```

> **Note:** Use the Docker Compose service name as the `host` value — e.g. `postgres`, `mysql` — not `localhost`.

---

### With TimescaleDB

```yaml
services:
  db-mcp-server:
    image: mekayelanik/db-mcp-server:latest
    container_name: db-mcp-server
    restart: unless-stopped
    ports:
      - "9092:9092"
    volumes:
      - ./config.json:/app/config.json:ro
      - logs:/app/logs
    depends_on:
      timescaledb:
        condition: service_healthy
    networks:
      - mcp-net

  timescaledb:
    image: timescale/timescaledb-ha:pg16
    container_name: mcp-timescaledb
    restart: unless-stopped
    environment:
      POSTGRES_DB: tsdb
      POSTGRES_USER: tsuser
      POSTGRES_PASSWORD: tspassword
    volumes:
      - timescale-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U tsuser -d tsdb"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - mcp-net

volumes:
  timescale-data:
  logs:

networks:
  mcp-net:
    driver: bridge
```

---

### With SQLite (file-based)

```yaml
services:
  db-mcp-server:
    image: mekayelanik/db-mcp-server:latest
    container_name: db-mcp-server
    restart: unless-stopped
    ports:
      - "9092:9092"
    volumes:
      - ./config.json:/app/config.json:ro
      - ./data:/app/data          # SQLite database files live here
      - logs:/app/logs
    environment:
      TRANSPORT_MODE: sse

volumes:
  logs:
```

`config.json`:

```json
{
  "connections": [
    {
      "id": "sqlite_app",
      "type": "sqlite",
      "database_path": "/app/data/app.db",
      "journal_mode": "WAL",
      "cache_size": 2000,
      "use_modernc_driver": true
    }
  ]
}
```

---

## Networking

### Connecting to Databases on the Host Machine

When your databases run on the host (not in Docker), use `host.docker.internal` instead of `localhost`:

```json
{
  "connections": [
    {
      "id": "host_postgres",
      "type": "postgres",
      "host": "host.docker.internal",
      "port": 5432,
      "name": "mydb",
      "user": "myuser",
      "password": "mypassword"
    }
  ]
}
```

On Linux, `host.docker.internal` requires adding `--add-host`:

```bash
docker run -d \
  --name db-mcp-server \
  -p 9092:9092 \
  --add-host host.docker.internal:host-gateway \
  -v $(pwd)/config.json:/app/config.json \
  mekayelanik/db-mcp-server:latest
```

Or in Docker Compose:

```yaml
services:
  db-mcp-server:
    image: mekayelanik/db-mcp-server:latest
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

---

### Joining an Existing Network

If your databases are already running on a named Docker network:

```bash
docker run -d \
  --name db-mcp-server \
  -p 9092:9092 \
  --network my-existing-network \
  -v $(pwd)/config.json:/app/config.json \
  mekayelanik/db-mcp-server:latest
```

In Docker Compose, attach to an external network:

```yaml
services:
  db-mcp-server:
    image: mekayelanik/db-mcp-server:latest
    networks:
      - my-existing-network

networks:
  my-existing-network:
    external: true
```

---

### Exposing to LAN / Remote Clients

By default the container binds to all interfaces (`0.0.0.0`). To restrict to a specific host IP:

```bash
docker run -d \
  --name db-mcp-server \
  -p 192.168.1.100:9092:9092 \
  -v $(pwd)/config.json:/app/config.json \
  mekayelanik/db-mcp-server:latest
```

---

### Behind a Reverse Proxy (nginx example)

```nginx
upstream db_mcp {
    server 127.0.0.1:9092;
}

server {
    listen 443 ssl;
    server_name mcp.example.com;

    location / {
        proxy_pass         http://db_mcp;
        proxy_http_version 1.1;

        # Required for SSE (Server-Sent Events)
        proxy_set_header   Connection '';
        proxy_buffering    off;
        proxy_cache        off;
        chunked_transfer_encoding on;

        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}
```

---

## Security & Transport

### Should HTTPS be default?

Current default is `ENABLE_HTTPS=true`.

Recommended practice:
- Local-only development: HTTPS is still recommended, but you can set `ENABLE_HTTPS=false` for tools that only support HTTP.
- Any remote/LAN/public use: use HTTPS and API key auth.

### What transport does this MCP expose?

Application transport modes:
- `sse` (default) via HTTP(S)
- `stdio` (for local command-based integrations)

When running in container server mode (`TRANSPORT_MODE=sse`):
- Public listener: HAProxy on `SERVER_PORT` (default `9092`)
- Internal app listener: MCP server on `INTERNAL_SERVER_PORT` (default `38011`, local-only in container)

Common MCP HTTP endpoints exposed by upstream server include:
- `/sse`
- `/jsonrpc`
- `/message`
- `/events`
- `/status`

### API key authentication behavior

Set `API_KEY` to enable Bearer token protection in HAProxy.

Expected status behavior:
- Missing auth header -> `401 Unauthorized`
- Invalid key -> `403 Forbidden`
- Valid key -> request is forwarded to backend (backend may still return `200`, `204`, `405`, etc., depending on endpoint/method)

Notes:
- `Bearer` scheme is matched case-insensitively (`Bearer`/`bearer` both work).
- Invalid API key format is fail-closed: container exits at startup.
- `/healthz` has a localhost-only bypass for internal health checks.

### HTTPS and certificate behavior

If `ENABLE_HTTPS=true`, HAProxy serves TLS on `SERVER_PORT`.
Default minimum TLS version is `TLSv1.3`.

### HTTP protocol versions (optional mode)

Set `HTTP_VERSION_MODE` to control protocol negotiation on the public listener:
- `auto` (default): try `h3` first, then fall back to `h2`, then `h1` (`http/1.1`)
- `all`: same behavior as `auto`
- `h1`: force HTTP/1.1 only
- `h2`: force HTTP/2 over TLS only
- `h1+h2`: allow both HTTP/1.1 and HTTP/2
- `h3`: request HTTP/3 support (QUIC) plus standard TLS fallback (`h1+h2`)

Notes:
- `h2` and `h3` require TLS (`ENABLE_HTTPS=true`).
- If `ENABLE_HTTPS=false`, the listener falls back to HTTP/1.1.
- If `h3` is requested but QUIC is unavailable in the HAProxy build, startup logs a warning and continues without `h3`.

#### Recommended defaults and mode intent

- Production default: `HTTP_VERSION_MODE=auto`
- `auto` / `all`: try HTTP/3 first, then HTTP/2, then HTTP/1.1 fallback
- `h1`: strict compatibility mode
- `h2`: force HTTP/2-only over TLS
- `h3`: request HTTP/3 with safe TCP fallback

#### Docker CLI examples by mode

Auto chain (`h3 -> h2 -> h1`) (default):

```bash
docker run -d \
  --name db-mcp-auto \
  -p 9092:9092 \
  -p 9092:9092/udp \
  -v $(pwd)/config.json:/app/config.json:ro \
  -e ENABLE_HTTPS=true \
  -e HTTP_VERSION_MODE=auto \
  -e API_KEY='replace_with_a_strong_key' \
  mekayelanik/db-mcp-server:latest
```

HTTP/1.1 only:

```bash
docker run -d \
  --name db-mcp-h1 \
  -p 9092:9092 \
  -v $(pwd)/config.json:/app/config.json:ro \
  -e ENABLE_HTTPS=true \
  -e HTTP_VERSION_MODE=h1 \
  -e API_KEY='replace_with_a_strong_key' \
  mekayelanik/db-mcp-server:latest
```

HTTP/2 only:

```bash
docker run -d \
  --name db-mcp-h2 \
  -p 9092:9092 \
  -v $(pwd)/config.json:/app/config.json:ro \
  -e ENABLE_HTTPS=true \
  -e HTTP_VERSION_MODE=h2 \
  -e API_KEY='replace_with_a_strong_key' \
  mekayelanik/db-mcp-server:latest
```

HTTP/3 requested (plus fallback):

```bash
docker run -d \
  --name db-mcp-h3 \
  -p 9092:9092 \
  -p 9092:9092/udp \
  -v $(pwd)/config.json:/app/config.json:ro \
  -e ENABLE_HTTPS=true \
  -e HTTP_VERSION_MODE=h3 \
  -e API_KEY='replace_with_a_strong_key' \
  mekayelanik/db-mcp-server:latest
```

#### Docker Compose snippet

```yaml
services:
  db-mcp-server:
    image: mekayelanik/db-mcp-server:latest
    ports:
      - "9092:9092/tcp"
      - "9092:9092/udp"
    environment:
      ENABLE_HTTPS: "true"
      HTTP_VERSION_MODE: "auto"
      API_KEY: "replace_with_a_strong_key"
    volumes:
      - ./config.json:/app/config.json:ro
```

#### How to verify effective mode at runtime

Check startup logs:

```bash
docker logs db-mcp-auto | grep -E 'HTTP versions enabled|HTTPS enabled|falling back'
```

Inspect generated HAProxy binds:

```bash
docker exec db-mcp-auto sh -lc "grep -n 'bind ' /tmp/haproxy.cfg"
```

Expected for `auto`/`all` when QUIC is available:
- one TLS TCP bind with ALPN `h2,http/1.1`
- one QUIC bind with ALPN `h3`

Expected for `h1`:
- one TLS TCP bind with ALPN `http/1.1`

Certificate precedence:
1. If `TLS_PEM_PATH` exists, it is used directly.
2. Else if both `TLS_CERT_PATH` and `TLS_KEY_PATH` exist, they are combined into PEM.
3. Else a self-signed cert is auto-generated using `TLS_CN` and `TLS_SAN`.

### Using Cloudflare Origin Certificate (recommended behind Cloudflare)

If your traffic is proxied through Cloudflare, use a Cloudflare Origin Certificate instead of the auto-generated self-signed cert.

1. In Cloudflare Dashboard, create an Origin Certificate for your hostname(s), for example `mcp.example.com`.
2. Save certificate and private key PEM content to host files.

```bash
mkdir -p certs

# Paste certificate PEM from Cloudflare
cat > certs/cloudflare-origin.crt <<'EOF'
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
EOF

# Paste private key PEM from Cloudflare
cat > certs/cloudflare-origin.key <<'EOF'
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
EOF
```

3. Mount the files and point TLS env vars to them:

```bash
docker run -d \
  --name db-mcp-server \
  -p 9092:9092 \
  -v $(pwd)/config.json:/app/config.json:ro \
  -v $(pwd)/certs/cloudflare-origin.crt:/etc/haproxy/certs/server.crt:ro \
  -v $(pwd)/certs/cloudflare-origin.key:/etc/haproxy/certs/server.key:ro \
  -e ENABLE_HTTPS=true \
  -e TLS_CERT_PATH=/etc/haproxy/certs/server.crt \
  -e TLS_KEY_PATH=/etc/haproxy/certs/server.key \
  -e TLS_MIN_VERSION=TLSv1.3 \
  -e API_KEY='replace_with_a_strong_key' \
  mekayelanik/db-mcp-server:latest
```

Notes:
- The entrypoint combines `TLS_CERT_PATH` + `TLS_KEY_PATH` into `TLS_PEM_PATH` automatically.
- Keep key files out of git and restrict permissions (`chmod 600`).
- In Cloudflare, use SSL/TLS mode `Full (strict)`.

### Secure run example (recommended)

```bash
docker run -d \
  --name db-mcp-server \
  -p 9092:9092 \
  -v $(pwd)/config.json:/app/config.json:ro \
  -e TRANSPORT_MODE=sse \
  -e ENABLE_HTTPS=true \
  -e TLS_CN=localhost \
  -e TLS_SAN=DNS:localhost,IP:127.0.0.1 \
  -e API_KEY='replace_with_a_strong_key' \
  mekayelanik/db-mcp-server:latest
```

Then connect using:
- `https://localhost:9092/sse`

---

## Configuration

Create a `config.json` and mount it to `/app/config.json` inside the container.

### Multi-database example

```json
{
  "connections": [
    {
      "id": "pg_main",
      "type": "postgres",
      "host": "postgres",
      "port": 5432,
      "name": "maindb",
      "user": "appuser",
      "password": "apppassword",
      "query_timeout": 60,
      "max_open_conns": 20,
      "max_idle_conns": 5,
      "conn_max_lifetime_seconds": 300
    },
    {
      "id": "mysql_legacy",
      "type": "mysql",
      "host": "mysql",
      "port": 3306,
      "name": "legacydb",
      "user": "appuser",
      "password": "apppassword"
    },
    {
      "id": "sqlite_cache",
      "type": "sqlite",
      "database_path": "/app/data/cache.db",
      "journal_mode": "WAL",
      "use_modernc_driver": true
    },
    {
      "id": "oracle_erp",
      "type": "oracle",
      "host": "oracle.internal",
      "port": 1521,
      "service_name": "PROD",
      "user": "appuser",
      "password": "apppassword"
    }
  ]
}
```

---

## Supported Databases

| Database | Status | Notes |
|---|---|---|
| PostgreSQL | ✅ Full support (v9.6–17) | Queries, transactions, schema, performance |
| MySQL | ✅ Full support | Queries, transactions, schema, performance |
| SQLite | ✅ Full support | File-based, in-memory, SQLCipher encryption |
| Oracle | ✅ Full support (10g–23c) | Standard, RAC, Cloud Wallet, TNS |
| TimescaleDB | ✅ Full support | Hypertables, continuous aggregates, retention policies |

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `SERVER_PORT` | `9092` | Public HAProxy listener port |
| `INTERNAL_SERVER_PORT` | `38011` | Internal MCP server port (inside container) |
| `TRANSPORT_MODE` | `sse` | Transport mode: `sse` or `stdio` |
| `CONFIG_PATH` | `/app/config.json` | Path to the database config file inside the container |
| `API_KEY` | *(empty)* | Enables Bearer auth when set (validated at startup) |
| `ENABLE_HTTPS` | `true` | Enables TLS termination in HAProxy |
| `TLS_CERT_PATH` | `/etc/haproxy/certs/server.crt` | Certificate file path |
| `TLS_KEY_PATH` | `/etc/haproxy/certs/server.key` | Private key file path |
| `TLS_PEM_PATH` | `/etc/haproxy/certs/server.pem` | PEM bundle path used by HAProxy |
| `TLS_CN` | `localhost` | CN used for auto-generated self-signed cert |
| `TLS_SAN` | `DNS:localhost` | SAN used for auto-generated self-signed cert |
| `TLS_DAYS` | `365` | Validity period for auto-generated self-signed cert |
| `TLS_MIN_VERSION` | `TLSv1.3` | Minimum accepted TLS version for HTTPS listener (`TLSv1.2` or `TLSv1.3`) |
| `HTTP_VERSION_MODE` | `auto` | Public listener HTTP version mode: `auto`, `all`, `h1`, `h2`, `h1+h2`, `h3` |

---

## AI Client Integration

Most MCP clients (Claude Code, Codex-style clients, Cursor, VS Code extensions, and custom agents) accept one of these patterns:
- URL-based MCP server over SSE (HTTP or HTTPS)
- Command-based MCP server over STDIO

The exact config file path differs per client, but the JSON object under `mcpServers` is usually similar.

### Template A: HTTP + SSE

Use this for local trusted development only.

```json
{
  "mcpServers": {
    "db-mcp-http": {
      "url": "http://localhost:9092/sse"
    }
  }
}
```

### Template B: HTTPS + SSE + Bearer API key

Recommended for LAN/remote use.

```json
{
  "mcpServers": {
    "db-mcp-https": {
      "url": "https://localhost:9092/sse",
      "headers": {
        "Authorization": "Bearer REPLACE_WITH_API_KEY"
      }
    }
  }
}
```

If your client validates certificates strictly, use a trusted cert (or configure trust for your self-signed cert).

### Template C: STDIO via Docker

Works well for local command-based clients (including Claude Desktop/CLI style integrations).

```json
{
  "mcpServers": {
    "db-mcp-stdio": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "-v", "/path/to/config.json:/app/config.json:ro",
        "-e", "TRANSPORT_MODE=stdio",
        "mekayelanik/db-mcp-server:latest"
      ]
    }
  }
}
```

### Claude Code example (HTTPS + SSE)

```json
{
  "mcpServers": {
    "db-mcp-server": {
      "url": "https://localhost:9092/sse",
      "headers": {
        "Authorization": "Bearer REPLACE_WITH_API_KEY"
      }
    }
  }
}
```

### Codex-style example (HTTPS + SSE)

```json
{
  "mcpServers": {
    "db-mcp-server": {
      "url": "https://localhost:9092/sse",
      "headers": {
        "Authorization": "Bearer REPLACE_WITH_API_KEY"
      }
    }
  }
}
```

### CLI templates

HTTP + SSE:

```bash
docker run -d \
  --name db-mcp-http \
  -p 9092:9092 \
  -e TRANSPORT_MODE=sse \
  -e ENABLE_HTTPS=false \
  -v $(pwd)/config.json:/app/config.json:ro \
  mekayelanik/db-mcp-server:latest
```

HTTPS + SSE + API key:

```bash
docker run -d \
  --name db-mcp-https \
  -p 9092:9092 \
  -e TRANSPORT_MODE=sse \
  -e ENABLE_HTTPS=true \
  -e TLS_MIN_VERSION=TLSv1.3 \
  -e TLS_CN=localhost \
  -e TLS_SAN=DNS:localhost,IP:127.0.0.1 \
  -e API_KEY='REPLACE_WITH_API_KEY' \
  -v $(pwd)/config.json:/app/config.json:ro \
  mekayelanik/db-mcp-server:latest
```

STDIO:

```bash
docker run --rm -i \
  -e TRANSPORT_MODE=stdio \
  -v $(pwd)/config.json:/app/config.json:ro \
  mekayelanik/db-mcp-server:latest
```

### Quick compatibility notes for Claude Code, Codex, and similar clients

- If your client supports URL-based MCP servers, prefer HTTPS + SSE template.
- If your client supports command-based MCP servers, use the STDIO template.
- If the client does not support custom headers in URL mode, place the container behind a trusted reverse proxy that injects auth, or use STDIO mode.

---

## License

This repository (build scripts, Dockerfile, workflow, and documentation) is licensed under the **[GNU General Public License v3.0](LICENSE)**.

The packaged application — **[FreePeak/db-mcp-server](https://github.com/FreePeak/db-mcp-server)** — is the work of [FreePeak](https://github.com/FreePeak) and contributors, and is separately licensed under the **[MIT License](https://github.com/FreePeak/db-mcp-server/blob/main/LICENSE)**. All credit for the application itself belongs to them.

---

<div align="center">

Built on top of [FreePeak/db-mcp-server](https://github.com/FreePeak/db-mcp-server)

</div>

---

## 😎 Buy Me a Coffee ☕︎

**Your support encourages me to keep creating/supporting my open-source projects.** If you found value in this project, you can buy me a coffee to keep me inspired.

<p align="center">
<a href="https://07mekayel07.gumroad.com/coffee" target="_blank">
<img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width="217" height="60">
</a>
</p>
