#!/usr/bin/env bash
# .github/smoke/run-smoke.sh
# =============================================================================
# Post-build MCP smoke battery for db-mcp-server-docker images.
#
# Usage:
#   bash run-smoke.sh <image_ref>
#
# Required env (defaults match .github/smoke/compose.yml + CI service):
#   PG_HOST     (default: localhost)
#   PG_PORT     (default: 5432)
#   PG_USER     (default: dbmcp)
#   PG_PASS     (default: smokepass)
#   PG_DB       (default: smoke_db)
#   MCP_PORT    (default: 39092)   external port to bind dbmcp container to
#   CONTAINER_NAME (default: dbmcp-smoke)
#
# Behavior:
#   1. Probe Postgres reachability + privileges + extension install
#   2. Bootstrap public.smoke_metrics hypertable + 60 rows
#   3. Pull the supplied image (if not cached)
#   4. Run the container with TRANSPORT_MODE=streamable-http, ENABLE_HTTPS=false,
#      mounting the smoke config; --network=host so it reaches Postgres on
#      localhost (works on Linux runners and Linux dev hosts)
#   5. Initialize an MCP session
#   6. Iterate every tool family, assert PASS conditions
#   7. Tally; exit 1 on any FAIL; dump container logs on FAIL
#   8. Always: drop hypertable, remove container
#
# PASS conditions per response:
#   - HTTP 200
#   - JSON parses
#   - .error absent AND .result.isError != true
#   - .result.content[0].text does NOT contain "map[content"
#     (FormatResponse double-wrap regression guard — defense-in-depth even
#     after upstream PR #67 lands)
# =============================================================================
set -uo pipefail

IMAGE_REF="${1:-}"
if [[ -z "$IMAGE_REF" ]]; then
  echo "usage: $0 <image_ref>"
  exit 64
fi

PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-dbmcp}"
PG_PASS="${PG_PASS:-smokepass}"
PG_DB="${PG_DB:-smoke_db}"
MCP_PORT="${MCP_PORT:-39092}"
CONTAINER_NAME="${CONTAINER_NAME:-dbmcp-smoke}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# CONFIG_PATH (in-script existence check) vs CONFIG_BIND_SRC (path the host
# docker daemon uses for the -v mount). They differ only when smoke runs
# inside a container sharing the host docker socket (DinD), where the
# daemon resolves mounts on the host filesystem, not in the calling
# container's view. In CI and on bare hosts they are identical.
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/db-mcp-config.json}"
CONFIG_BIND_SRC="${CONFIG_BIND_SRC:-${CONFIG_PATH}}"

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "FATAL: config not found at $CONFIG_PATH"
  exit 65
fi

BLUE='\033[1;34m'; GREEN='\033[1;32m'; RED='\033[1;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${BLUE}[smoke]${NC} $*"; }
ok()   { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }

PASS=0
FAIL=0
FAILS=()

# ─── Cleanup hook ───────────────────────────────────────────────────────────
cleanup() {
  log "Cleanup"
  PGPASSWORD="$PG_PASS" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" \
    -v ON_ERROR_STOP=0 -q -c 'DROP TABLE IF EXISTS public.smoke_metrics CASCADE;' \
    >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ─── 1. Postgres reachability + bootstrap ───────────────────────────────────
log "Probing Postgres at ${PG_HOST}:${PG_PORT} as ${PG_USER}/${PG_DB}"
if ! command -v psql >/dev/null 2>&1; then
  echo "FATAL: psql not found in PATH (install postgresql-client)"
  exit 65
fi

for i in 1 2 3 4 5 6 7 8 9 10; do
  if PGPASSWORD="$PG_PASS" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" \
       -tAc 'SELECT 1' >/dev/null 2>&1; then
    log "Postgres reachable"
    break
  fi
  warn "Postgres not ready (attempt $i/10) — sleeping 2s"
  sleep 2
  if [[ $i -eq 10 ]]; then
    echo "FATAL: Postgres unreachable after 10 attempts"
    exit 66
  fi
done

log "Bootstrapping public.smoke_metrics hypertable + 60 rows"
PGPASSWORD="$PG_PASS" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" \
  -v ON_ERROR_STOP=1 -q <<SQL
CREATE EXTENSION IF NOT EXISTS timescaledb;
DROP TABLE IF EXISTS public.smoke_metrics CASCADE;
CREATE TABLE public.smoke_metrics (
  ts     TIMESTAMPTZ NOT NULL,
  sensor TEXT NOT NULL,
  val    DOUBLE PRECISION
);
SELECT create_hypertable('public.smoke_metrics', 'ts');
INSERT INTO public.smoke_metrics
  SELECT now() - (i || ' minutes')::interval,
         CASE WHEN i % 2 = 0 THEN 'A' ELSE 'B' END,
         random() * 100
  FROM generate_series(1, 60) i;
SQL

# ─── 2. Pull + start dbmcp container ────────────────────────────────────────
log "Pulling image: ${IMAGE_REF}"
docker pull "$IMAGE_REF" >/dev/null

log "Starting container ${CONTAINER_NAME} (--network=host, MCP_PORT=${MCP_PORT})"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER_NAME" \
  --network=host \
  -e TRANSPORT_MODE=streamable-http \
  -e ENABLE_HTTPS=false \
  -e SERVER_PORT="$MCP_PORT" \
  -e CONFIG_PATH=/app/config.json \
  -v "${CONFIG_BIND_SRC}:/app/config.json:ro" \
  "$IMAGE_REF" >/dev/null

URL="http://localhost:${MCP_PORT}/mcp"
HEALTH="http://localhost:${MCP_PORT}/healthz"
H='Accept: application/json, text/event-stream'
CT='Content-Type: application/json'

log "Waiting for /healthz at ${HEALTH}"
HEALTH_OK=no
for i in $(seq 1 30); do
  if curl -fsS --max-time 2 "$HEALTH" >/dev/null 2>&1; then
    HEALTH_OK=yes
    log "Health OK after ${i}s"
    break
  fi
  sleep 1
done
if [[ "$HEALTH_OK" != "yes" ]]; then
  fail "Container never became healthy"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -60
  exit 1
fi

# ─── 3. MCP handshake ───────────────────────────────────────────────────────
log "MCP initialize"
INIT_RESP=$(curl -sS -i -X POST "$URL" -H "$CT" -H "$H" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0"}}}')
SID=$(printf '%s' "$INIT_RESP" | grep -i '^mcp-session-id:' | awk '{print $2}' | tr -d '\r' | head -1)
if [[ -z "$SID" ]]; then
  fail "No mcp-session-id returned by initialize"
  echo "$INIT_RESP" | head -20
  docker logs "$CONTAINER_NAME" 2>&1 | tail -40
  exit 1
fi
log "Session: ${SID}"

curl -sS -X POST "$URL" -H "$CT" -H "$H" -H "mcp-session-id: $SID" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' -o /dev/null

# ─── 4. Helper: call tool, extract response, run assertions ─────────────────
NEXT_ID=2
call() {
  local name="$1" args="$2"
  local id=$((NEXT_ID++))
  curl -sS -X POST "$URL" -H "$CT" -H "$H" -H "mcp-session-id: $SID" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":${id},\"method\":\"tools/call\",\"params\":{\"name\":\"${name}\",\"arguments\":${args}}}" \
    | grep '^data:' | sed 's/^data: //' | head -1
}

# extract_text <raw_response>
extract_text() {
  echo "$1" | jq -r '.result.content[0].text // .error.message // "null"' 2>/dev/null
}
# is_error <raw_response>
is_error() {
  local r; r=$(echo "$1" | jq -r '
    if .error then "yes"
    elif .result.isError == true then "yes"
    else "no" end' 2>/dev/null)
  [[ "$r" == "yes" ]]
}

# assert_tool_call <label> <name> <args>
assert_tool_call() {
  local label="$1" name="$2" args="$3"
  local raw text
  raw=$(call "$name" "$args")
  if [[ -z "$raw" ]]; then
    FAIL=$((FAIL+1)); FAILS+=("$label: empty response")
    fail "$label  →  empty response"; return 1
  fi
  if is_error "$raw"; then
    FAIL=$((FAIL+1)); FAILS+=("$label: tool error — $(echo "$raw" | jq -r '.error.message // .result.content[0].text // ""' | head -c 200)")
    fail "$label  →  tool error"; return 1
  fi
  text=$(extract_text "$raw")
  if echo "$text" | grep -q 'map\[content'; then
    FAIL=$((FAIL+1)); FAILS+=("$label: FormatResponse double-wrap regression — text contains 'map[content'")
    fail "$label  →  REGRESSION: 'map[content' present in text"; return 1
  fi
  PASS=$((PASS+1))
  ok "$label"
  return 0
}

# ─── 5. Tools/list sanity ───────────────────────────────────────────────────
log "Listing tools"
TOOLS_LIST_RAW=$(curl -sS -X POST "$URL" -H "$CT" -H "$H" -H "mcp-session-id: $SID" \
  -d '{"jsonrpc":"2.0","id":99,"method":"tools/list"}' | grep '^data:' | sed 's/^data: //' | head -1)
TOOL_COUNT=$(echo "$TOOLS_LIST_RAW" | jq -r '.result.tools | length' 2>/dev/null || echo 0)
N_FAMILIES=$(echo "$TOOLS_LIST_RAW" | jq -r '
  .result.tools | map(.name | sub("_smoke_db$"; "")) | unique | length' 2>/dev/null || echo 0)
log "Found ${TOOL_COUNT} tools, ${N_FAMILIES} unique families"
if [[ "$N_FAMILIES" -lt 8 ]]; then
  fail "tools/list returned only ${N_FAMILIES} unique families (expected ≥8)"
  FAIL=$((FAIL+1)); FAILS+=("tools/list count too low: ${N_FAMILIES}")
else
  PASS=$((PASS+1)); ok "tools/list returned ${N_FAMILIES} families"
fi

# ─── 6. Per-tool battery ────────────────────────────────────────────────────
log "=== Tool battery ==="
DB=smoke_db

assert_tool_call "query_${DB}"            "query_${DB}"   '{"query":"SELECT count(*) AS n FROM public.smoke_metrics"}'
assert_tool_call "query_${DB} param"      "query_${DB}"   '{"query":"SELECT $1::int + $2::int AS s","params":["3","4"]}'
assert_tool_call "execute_${DB}"          "execute_${DB}" "{\"statement\":\"INSERT INTO public.smoke_metrics VALUES (now(),'X',1.23)\"}"
assert_tool_call "schema_${DB}"           "schema_${DB}"  '{}'

# transaction round-trip
TX_BEGIN=$(call "transaction_${DB}" '{"action":"begin","readOnly":false}')
TID=$(echo "$TX_BEGIN" | grep -oE 'tx_[A-Za-z0-9_]+' | head -1)
if [[ -n "$TID" ]]; then
  PASS=$((PASS+1)); ok "transaction_${DB} begin (tid=${TID})"
  assert_tool_call "transaction_${DB} execute" "transaction_${DB}" \
    "{\"action\":\"execute\",\"transactionId\":\"${TID}\",\"statement\":\"INSERT INTO public.smoke_metrics VALUES (now(),'TX',9.99)\"}"
  assert_tool_call "transaction_${DB} commit"  "transaction_${DB}" \
    "{\"action\":\"commit\",\"transactionId\":\"${TID}\"}"
else
  FAIL=$((FAIL+1)); FAILS+=("transaction_${DB} begin: no tid")
  fail "transaction_${DB} begin  →  no tid"
fi

TX_RO=$(call "transaction_${DB}" '{"action":"begin","readOnly":true}')
RTID=$(echo "$TX_RO" | grep -oE 'tx_[A-Za-z0-9_]+' | head -1)
if [[ -n "$RTID" ]]; then
  assert_tool_call "transaction_${DB} rollback" "transaction_${DB}" \
    "{\"action\":\"rollback\",\"transactionId\":\"${RTID}\"}"
else
  FAIL=$((FAIL+1)); FAILS+=("transaction_${DB} ro-begin: no tid")
  fail "transaction_${DB} ro-begin  →  no tid"
fi

# performance: 5 actions
assert_tool_call "performance_${DB} getMetrics"     "performance_${DB}" '{"action":"getMetrics"}'
assert_tool_call "performance_${DB} getSlowQueries" "performance_${DB}" '{"action":"getSlowQueries","limit":5}'
assert_tool_call "performance_${DB} setThreshold"   "performance_${DB}" '{"action":"setThreshold","threshold":100}'
assert_tool_call "performance_${DB} analyzeQuery"   "performance_${DB}" '{"action":"analyzeQuery","query":"SELECT count(*) FROM public.smoke_metrics"}'
assert_tool_call "performance_${DB} reset"          "performance_${DB}" '{"action":"reset"}'

# timescale
assert_tool_call "timescaledb_timeseries_query_${DB}" "timescaledb_timeseries_query_${DB}" \
  '{"operation":"time_series_query","target_table":"public.smoke_metrics","time_column":"ts","bucket_interval":"5 minutes","aggregations":"AVG(val) AS avg_val,COUNT(*) AS n","start_time":"2020-01-01","end_time":"2030-01-01","limit":"5"}'
assert_tool_call "timescaledb_analyze_timeseries_${DB}" "timescaledb_analyze_timeseries_${DB}" \
  '{"operation":"analyze_time_series","target_table":"public.smoke_metrics","time_column":"ts","start_time":"2020-01-01","end_time":"2030-01-01"}'

# global
assert_tool_call "list_databases" list_databases '{"path":"/app"}'
assert_tool_call "list"           list           '{"path":"/app"}'

# ─── 7. Verdict ─────────────────────────────────────────────────────────────
echo
TOTAL=$((PASS + FAIL))
log "================================================="
if [[ $FAIL -eq 0 ]]; then
  ok "ALL SMOKE CHECKS PASSED  (${PASS}/${TOTAL})"
  exit 0
else
  fail "SMOKE FAILED  (${FAIL} fail / ${PASS} pass / ${TOTAL} total)"
  echo
  echo "=== Failure details ==="
  for f in "${FAILS[@]}"; do echo "  - $f"; done
  echo
  echo "=== Container logs (tail 80) ==="
  docker logs "$CONTAINER_NAME" 2>&1 | tail -80
  exit 1
fi
