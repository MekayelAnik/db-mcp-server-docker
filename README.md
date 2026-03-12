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

<h3>Unofficial multi-arch Docker image for <a href="https://github.com/FreePeak/db-mcp-server">FreePeak/db-mcp-server</a> — a powerful multi-database MCP server for AI assistants.</h3>

<div>
  <a href="#credits">Credits</a> •
  <a href="#images">Images</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#docker-cli">Docker CLI</a> •
  <a href="#docker-compose">Docker Compose</a> •
  <a href="#networking">Networking</a> •
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
- Automated image builds via GitHub Actions
- This Docker-focused usage documentation

For feature requests, bug reports, and source code contributions, please visit the [upstream repository](https://github.com/FreePeak/db-mcp-server).

---

## Images

Images are published to both registries on every upstream commit and are identical in content.

| Registry | Image |
|---|---|
| Docker Hub | `mekayelanik/db-mcp-server` |
| GHCR | `ghcr.io/mekayelanik/db-mcp-server` |

### Tags

| Tag | Description |
|---|---|
| `latest` | Latest build from upstream `main` |
| `stable` | Promoted after 5 days of `latest` stability |
| `YYYYMMDD-<sha>` | Immutable tag — exact upstream commit and build date, e.g. `20250312-19b7975` |
| `YYYYMMDD` | Floating date tag — latest build of that day |

### Platforms

| Platform | Architecture |
|---|---|
| `linux/amd64` | x86-64 (most servers, desktop Linux, WSL2) |
| `linux/arm64` | ARM 64-bit (Apple Silicon via Rosetta, AWS Graviton, Raspberry Pi 4/5) |
| `linux/arm/v7` | ARM 32-bit (Raspberry Pi 2/3, older ARM boards) |

---

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

The MCP server is now available at `http://localhost:9092/sse`.

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
| `SERVER_PORT` | `9092` | Port the server listens on |
| `TRANSPORT_MODE` | `sse` | Transport mode: `sse` or `stdio` |
| `CONFIG_PATH` | `/app/config.json` | Path to the database config file inside the container |

---

## AI Client Integration

### Cursor / VS Code (SSE mode)

```json
{
  "mcpServers": {
    "db-mcp-server": {
      "url": "http://localhost:9092/sse"
    }
  }
}
```

### Claude Desktop (STDIO mode via Docker)

```json
{
  "mcpServers": {
    "db-mcp-server": {
      "command": "docker",
      "args": [
        "run", "--rm", "-i",
        "-v", "/path/to/config.json:/app/config.json",
        "-e", "TRANSPORT_MODE=stdio",
        "mekayelanik/db-mcp-server:latest"
      ]
    }
  }
}
```

---

## License

This repository (build scripts, Dockerfile, workflow, and documentation) is licensed under the **[GNU General Public License v3.0](LICENSE)**.

The packaged application — **[FreePeak/db-mcp-server](https://github.com/FreePeak/db-mcp-server)** — is the work of [FreePeak](https://github.com/FreePeak) and contributors, and is separately licensed under the **[MIT License](https://github.com/FreePeak/db-mcp-server/blob/main/LICENSE)**. All credit for the application itself belongs to them.

---

<div align="center">

Built with ❤️ on top of [FreePeak/db-mcp-server](https://github.com/FreePeak/db-mcp-server)

</div>

---

## 😎 Buy Me a Coffee ☕︎

**Your support encourages me to keep creating/supporting my open-source projects.** If you found value in this project, you can buy me a coffee to keep me inspired.

<p align="center">
<a href="https://07mekayel07.gumroad.com/coffee" target="_blank">
<img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width="217" height="60">
</a>
</p>
