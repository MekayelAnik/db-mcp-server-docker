#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_PORT=9092
readonly DEFAULT_INTERNAL_PORT=38011
readonly DEFAULT_PROTOCOL="sse"
readonly SAFE_API_KEY_REGEX='^[A-Za-z0-9_:.@+=-]{5,128}$'
readonly HAPROXY_TEMPLATE="/etc/haproxy/haproxy.cfg.template"
readonly HAPROXY_CONFIG="/tmp/haproxy.cfg"

trim() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  printf '%s' "$var"
}

is_positive_int() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

validate_port() {
  local name="$1"
  local value="$2"
  local fallback="$3"

  if ! is_positive_int "$value" || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
    echo "Invalid ${name}='$value', using default ${fallback}"
    printf '%s' "$fallback"
    return
  fi

  printf '%s' "$value"
}

validate_api_key() {
  API_KEY="${API_KEY:-}"
  API_KEY="$(trim "$API_KEY")"

  if [[ -z "$API_KEY" ]]; then
    export API_KEY=""
    return
  fi

  if [[ ! "$API_KEY" =~ $SAFE_API_KEY_REGEX ]]; then
    echo "Invalid API_KEY format. Disabling API key auth."
    export API_KEY=""
    return
  fi

  export API_KEY
}

generate_haproxy_config() {
  if [[ ! -f "$HAPROXY_TEMPLATE" ]]; then
    echo "HAProxy template missing: $HAPROXY_TEMPLATE"
    exit 1
  fi

  local api_key_check
  if [[ -n "$API_KEY" ]]; then
    local escaped_key="$API_KEY"
    escaped_key="${escaped_key//\\/\\\\}"
    escaped_key="${escaped_key//\"/\\\"}"

    api_key_check="    # API Key authentication enabled (localhost /healthz excluded)
    acl auth_header_present var(txn.auth_header) -m found
    acl auth_valid var(txn.auth_header) -m str \"Bearer ${escaped_key}\"

    # Deny requests without valid authentication (except localhost health checks)
    http-request deny deny_status 401 content-type \"application/json\" string '{\"error\":\"Unauthorized\",\"message\":\"Valid API key required\"}' if !is_health_check !auth_header_present
    http-request deny deny_status 401 content-type \"application/json\" string '{\"error\":\"Unauthorized\",\"message\":\"Valid API key required\"}' if is_health_check !is_localhost !auth_header_present
    http-request deny deny_status 403 content-type \"application/json\" string '{\"error\":\"Forbidden\",\"message\":\"Invalid API key\"}' if !is_health_check auth_header_present !auth_valid
    http-request deny deny_status 403 content-type \"application/json\" string '{\"error\":\"Forbidden\",\"message\":\"Invalid API key\"}' if is_health_check !is_localhost auth_header_present !auth_valid"
  else
    api_key_check="    # API Key authentication disabled - all requests allowed"
  fi

  sed -e "s|__PORT__|${SERVER_PORT}|g" \
      -e "s|__INTERNAL_PORT__|${INTERNAL_SERVER_PORT}|g" \
      -e "s|__SERVER_NAME__|dbmcp|g" \
      -e "s|__CORS_PREFLIGHT_CONDITION__|{ always_false }|g" \
      -e "s|__CORS_RESPONSE_CONDITION__|{ always_false }|g" \
      "$HAPROXY_TEMPLATE" > "${HAPROXY_CONFIG}.tmp"

  awk -v replacement="$api_key_check" '
    /__API_KEY_CHECK__/ {
      print replacement
      next
    }
    /__CORS_CHECK__/ {
      print "    # CORS disabled"
      next
    }
    { print }
  ' "${HAPROXY_CONFIG}.tmp" > "$HAPROXY_CONFIG"

  rm -f "${HAPROXY_CONFIG}.tmp"

  haproxy -c -f "$HAPROXY_CONFIG" >/dev/null
}

start_server() {
  local protocol="${TRANSPORT_MODE:-$DEFAULT_PROTOCOL}"
  local config_path="${CONFIG_PATH:-/app/config.json}"

  echo "Starting MCP server on internal port ${INTERNAL_SERVER_PORT}"
  /app/server -t "$protocol" -p "$INTERNAL_SERVER_PORT" -c "$config_path" &
  SERVER_PID=$!

  local i=0
  until nc -z 127.0.0.1 "$INTERNAL_SERVER_PORT" >/dev/null 2>&1; do
    if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
      echo "MCP server exited before becoming ready"
      return 1
    fi
    i=$((i + 1))
    if [ "$i" -ge 30 ]; then
      echo "MCP server did not become ready on ${INTERNAL_SERVER_PORT}"
      return 1
    fi
    sleep 1
  done
}

start_haproxy() {
  echo "Starting HAProxy on external port ${SERVER_PORT}"
  haproxy -db -f "$HAPROXY_CONFIG" &
  HAPROXY_PID=$!
}

shutdown() {
  set +e
  if [[ -n "${HAPROXY_PID:-}" ]]; then
    kill "$HAPROXY_PID" 2>/dev/null || true
  fi
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  wait 2>/dev/null || true
}

main() {
  # Support command passthrough for debugging/maintenance scenarios.
  if [[ $# -gt 0 ]]; then
    exec "$@"
  fi

  SERVER_PORT="${SERVER_PORT:-$DEFAULT_PORT}"
  INTERNAL_SERVER_PORT="${INTERNAL_SERVER_PORT:-$DEFAULT_INTERNAL_PORT}"

  SERVER_PORT="$(validate_port "SERVER_PORT" "$SERVER_PORT" "$DEFAULT_PORT")"
  INTERNAL_SERVER_PORT="$(validate_port "INTERNAL_SERVER_PORT" "$INTERNAL_SERVER_PORT" "$DEFAULT_INTERNAL_PORT")"

  validate_api_key
  generate_haproxy_config
  start_server
  start_haproxy

  if [[ -n "$API_KEY" ]]; then
    echo "API key authentication enabled"
  else
    echo "API key authentication disabled"
  fi

  trap shutdown SIGINT SIGTERM EXIT

  wait -n "$SERVER_PID" "$HAPROXY_PID"
}

main "$@"
