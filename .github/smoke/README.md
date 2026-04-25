# Post-build MCP smoke battery

Validates that a freshly-built `db-mcp-server` image actually serves a working
MCP `tools/call` surface against a real PostgreSQL+TimescaleDB backend.

Catches regressions that build-time checks miss:
- Upstream formatter quirks (e.g. the `map[content:[map[text:...]]]` envelope
  double-wrap bug surfaced 2026-04-25 → upstream PR #67)
- Wrong binary path, broken supergateway link, missing TLS certs, mis-routed
  HAProxy, busted entrypoint env wiring
- Drift in MCP transport / handshake / tool families

## What it does

1. Connect to a Postgres reachable at `${PG_HOST}:${PG_PORT}` (default
   `localhost:5432`)
2. `CREATE EXTENSION IF NOT EXISTS timescaledb`, build a `public.smoke_metrics`
   hypertable with 60 sample rows
3. `docker pull` the image under test, `docker run` it with
   `TRANSPORT_MODE=streamable-http`, `ENABLE_HTTPS=false`, mounting
   `db-mcp-config.json` at `/app/config.json`. Uses `--network=host` so the
   container reaches Postgres via `localhost`
4. Wait for `/healthz`, do the MCP `initialize` handshake
5. Iterate every tool family (query, execute, schema, transaction,
   performance, timescaledb time-series, list_databases, list) — assert each
   call: HTTP 200, JSON parses, no `.error` / `.result.isError`, and the
   response text does NOT contain `map[content` (regression guard)
6. Tally PASS/FAIL. `exit 1` on any FAIL with container logs dumped

## CI usage

Invoked by the `smoke-test` job in `.github/workflows/docker-publish.yml`
after `merge-manifest` writes the final tags and before `sync-registries`
mirrors them to Docker Hub. A smoke failure stops the mirror.

## Local debugging

```sh
docker compose -f .github/smoke/compose.yml up -d postgres
bash .github/smoke/run-smoke.sh ghcr.io/mekayelanik/db-mcp-server:nightly
docker compose -f .github/smoke/compose.yml down -v
```

Requirements on the host: `bash`, `curl`, `jq`, `psql`
(`postgresql-client`), `docker`. All present on `ubuntu-latest` GitHub
runners by default.

## Tunables (env vars)

| Var | Default | Purpose |
|---|---|---|
| `PG_HOST` | `localhost` | Postgres hostname |
| `PG_PORT` | `5432` | Postgres port |
| `PG_USER` | `dbmcp` | Postgres user (must own `smoke_db` or have `CREATE` on `public`) |
| `PG_PASS` | `smokepass` | Postgres password |
| `PG_DB`   | `smoke_db` | Postgres database |
| `MCP_PORT` | `39092` | External port to bind dbmcp to (defaults differ from 9092 to avoid collisions) |
| `CONTAINER_NAME` | `dbmcp-smoke` | Docker container name (auto-removed on exit) |
