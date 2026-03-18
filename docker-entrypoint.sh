#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_PORT=9092
readonly DEFAULT_INTERNAL_PORT=38011
readonly DEFAULT_PROTOCOL="sse"
readonly DEFAULT_TLS_DAYS=365
readonly DEFAULT_TLS_CN="localhost"
readonly DEFAULT_TLS_MIN_VERSION="TLSv1.3"
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

is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
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
    echo "Invalid API_KEY format. Refusing to start with malformed API key." >&2
    return 1
  fi

  export API_KEY
}

validate_tls_days() {
  local value="$1"
  local fallback="$2"

  if ! is_positive_int "$value"; then
    echo "Invalid TLS_DAYS='$value', using default ${fallback}"
    printf '%s' "$fallback"
    return
  fi

  printf '%s' "$value"
}

validate_tls_min_version() {
  local value="$1"
  local fallback="$2"

  case "$value" in
    TLSv1.2|TLSv1.3)
      printf '%s' "$value"
      ;;
    *)
      echo "Invalid TLS_MIN_VERSION='$value', using default ${fallback}" >&2
      printf '%s' "$fallback"
      ;;
  esac
}

ensure_parent_dir() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
}

prepare_tls_pem() {
  local cert_path="$1"
  local key_path="$2"
  local pem_path="$3"
  local tls_days="$4"
  local tls_cn="$5"
  local tls_san="$6"

  if [[ -f "$pem_path" ]]; then
    return
  fi

  ensure_parent_dir "$pem_path"

  if [[ -f "$cert_path" && -f "$key_path" ]]; then
    cat "$cert_path" "$key_path" > "$pem_path"
    chmod 600 "$pem_path"
    return
  fi

  echo "TLS enabled and no certificate material found; generating self-signed certificate (CN=${tls_cn})"
  ensure_parent_dir "$cert_path"
  ensure_parent_dir "$key_path"

  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$key_path" \
    -out "$cert_path" \
    -days "$tls_days" \
    -subj "/CN=${tls_cn}" \
    -addext "subjectAltName=${tls_san}" >/dev/null 2>&1

  chmod 600 "$cert_path" "$key_path"
  cat "$cert_path" "$key_path" > "$pem_path"
  chmod 600 "$pem_path"
}

escape_sed_replacement() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

escape_haproxy_regex() {
  local value="$1"
  local escaped=""
  local i ch

  for ((i = 0; i < ${#value}; i++)); do
    ch="${value:i:1}"
    if [[ "$ch" =~ [\\.^$\|?*+(){}\[\]] ]]; then
      escaped+="\\$ch"
    else
      escaped+="$ch"
    fi
  done

  printf '%s' "$escaped"
}

generate_haproxy_config() {
  if [[ ! -f "$HAPROXY_TEMPLATE" ]]; then
    echo "HAProxy template missing: $HAPROXY_TEMPLATE"
    exit 1
  fi

  local api_key_check
  if [[ -n "$API_KEY" ]]; then
    local escaped_key_regex
    escaped_key_regex="$(escape_haproxy_regex "$API_KEY")"

    api_key_check="    # API Key authentication enabled (localhost /healthz excluded)
    acl auth_header_present var(txn.auth_header) -m found
    acl auth_valid var(txn.auth_header) -m reg ^[Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+${escaped_key_regex}$

    # Deny requests without valid authentication (except localhost health checks)
    http-request deny deny_status 401 content-type \"application/json\" string '{\"error\":\"Unauthorized\",\"message\":\"Valid API key required\"}' if !is_health_check !auth_header_present
    http-request deny deny_status 401 content-type \"application/json\" string '{\"error\":\"Unauthorized\",\"message\":\"Valid API key required\"}' if is_health_check !is_localhost !auth_header_present
    http-request deny deny_status 403 content-type \"application/json\" string '{\"error\":\"Forbidden\",\"message\":\"Invalid API key\"}' if !is_health_check auth_header_present !auth_valid
    http-request deny deny_status 403 content-type \"application/json\" string '{\"error\":\"Forbidden\",\"message\":\"Invalid API key\"}' if is_health_check !is_localhost auth_header_present !auth_valid"
  else
    api_key_check="    # API Key authentication disabled - all requests allowed"
  fi

  local escaped_bind_directive
  escaped_bind_directive="$(escape_sed_replacement "${BIND_DIRECTIVE}")"

  sed -e "s|__BIND_DIRECTIVE__|${escaped_bind_directive}|g" \
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
  ENABLE_HTTPS="${ENABLE_HTTPS:-true}"
  TLS_CERT_PATH="${TLS_CERT_PATH:-/etc/haproxy/certs/server.crt}"
  TLS_KEY_PATH="${TLS_KEY_PATH:-/etc/haproxy/certs/server.key}"
  TLS_PEM_PATH="${TLS_PEM_PATH:-/etc/haproxy/certs/server.pem}"
  TLS_CN="${TLS_CN:-$DEFAULT_TLS_CN}"
  TLS_SAN="${TLS_SAN:-DNS:${TLS_CN}}"
  TLS_DAYS="${TLS_DAYS:-$DEFAULT_TLS_DAYS}"
  TLS_MIN_VERSION="${TLS_MIN_VERSION:-$DEFAULT_TLS_MIN_VERSION}"

  SERVER_PORT="$(validate_port "SERVER_PORT" "$SERVER_PORT" "$DEFAULT_PORT")"
  INTERNAL_SERVER_PORT="$(validate_port "INTERNAL_SERVER_PORT" "$INTERNAL_SERVER_PORT" "$DEFAULT_INTERNAL_PORT")"
  TLS_DAYS="$(validate_tls_days "$TLS_DAYS" "$DEFAULT_TLS_DAYS")"
  TLS_MIN_VERSION="$(validate_tls_min_version "$TLS_MIN_VERSION" "$DEFAULT_TLS_MIN_VERSION")"

  validate_api_key

  if is_true "$ENABLE_HTTPS"; then
    prepare_tls_pem "$TLS_CERT_PATH" "$TLS_KEY_PATH" "$TLS_PEM_PATH" "$TLS_DAYS" "$TLS_CN" "$TLS_SAN"
    BIND_DIRECTIVE="bind *:${SERVER_PORT} ssl crt ${TLS_PEM_PATH} ssl-min-ver ${TLS_MIN_VERSION}"
  else
    BIND_DIRECTIVE="bind *:${SERVER_PORT}"
  fi

  generate_haproxy_config
  start_server
  start_haproxy

  if [[ -n "$API_KEY" ]]; then
    echo "API key authentication enabled"
  else
    echo "API key authentication disabled"
  fi

  if is_true "$ENABLE_HTTPS"; then
    echo "HTTPS enabled on port ${SERVER_PORT}"
  else
    echo "HTTPS disabled; serving HTTP on port ${SERVER_PORT}"
  fi

  trap shutdown SIGINT SIGTERM EXIT

  wait -n "$SERVER_PID" "$HAPROXY_PID"
}

main "$@"
