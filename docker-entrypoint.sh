#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_PORT=9092
readonly DEFAULT_INTERNAL_PORT=38011
readonly DEFAULT_PROTOCOL="sse"
readonly DEFAULT_TLS_DAYS=365
readonly DEFAULT_TLS_CN="localhost"
readonly DEFAULT_TLS_MIN_VERSION="TLSv1.3"
readonly DEFAULT_HTTP_VERSION_MODE="auto"
readonly SAFE_API_KEY_REGEX='^[[:graph:]]+$'
readonly MIN_API_KEY_LEN=5
readonly MAX_API_KEY_LEN=256
readonly HAPROXY_TEMPLATE="/etc/haproxy/haproxy.cfg.template"
readonly HAPROXY_CONFIG="/tmp/haproxy.cfg"
readonly DEFAULT_PUID=1000
readonly DEFAULT_PGID=1000
readonly FIRST_RUN_FILE="/tmp/first_run_complete"

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

handle_first_run() {
  local uid_gid_changed=0

  if [[ -z "${PUID:-}" && -z "${PGID:-}" ]]; then
    PUID="$DEFAULT_PUID"
    PGID="$DEFAULT_PGID"
  elif [[ -n "${PUID:-}" && -z "${PGID:-}" ]]; then
    if is_positive_int "$PUID"; then
      PGID="$PUID"
    else
      PUID="$DEFAULT_PUID"
      PGID="$DEFAULT_PGID"
    fi
  elif [[ -z "${PUID:-}" && -n "${PGID:-}" ]]; then
    if is_positive_int "$PGID"; then
      PUID="$PGID"
    else
      PUID="$DEFAULT_PUID"
      PGID="$DEFAULT_PGID"
    fi
  else
    if ! is_positive_int "$PUID"; then
      PUID="$DEFAULT_PUID"
    fi
    if ! is_positive_int "$PGID"; then
      PGID="$DEFAULT_PGID"
    fi
  fi

  # Alpine uses addgroup/adduser instead of groupmod/usermod
  if ! getent group appgrp >/dev/null 2>&1; then
    addgroup -g "$PGID" appgrp 2>/dev/null || true
  fi
  if ! getent passwd appuser >/dev/null 2>&1; then
    adduser -D -u "$PUID" -G appgrp -h /app appuser 2>/dev/null || true
  fi

  # Update UID/GID if they differ
  if id appuser >/dev/null 2>&1; then
    local current_uid current_gid
    current_uid="$(id -u appuser)"
    current_gid="$(id -g appuser)"
    if [ "$current_uid" -ne "$PUID" ]; then
      deluser appuser 2>/dev/null || true
      adduser -D -u "$PUID" -G appgrp -h /app appuser 2>/dev/null || true
      uid_gid_changed=1
    fi
    if [ "$current_gid" -ne "$PGID" ]; then
      delgroup appgrp 2>/dev/null || true
      addgroup -g "$PGID" appgrp 2>/dev/null || true
      adduser appuser appgrp 2>/dev/null || true
      uid_gid_changed=1
    fi
  fi

  if [ "$uid_gid_changed" -eq 1 ]; then
    echo "Updated UID/GID to PUID=${PUID}, PGID=${PGID}"
  fi

  # Ensure app directories are owned correctly
  chown -R "${PUID}:${PGID}" /app/data /app/logs 2>/dev/null || true

  touch "$FIRST_RUN_FILE"
}

validate_port() {
  local name="$1"
  local value="$2"
  local fallback="$3"

  if ! is_positive_int "$value" || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
    echo "Invalid ${name}='$value', using default ${fallback}" >&2
    printf '%s' "$fallback"
    return
  fi

  printf '%s' "$value"
}

validate_api_key() {
  API_KEY="${API_KEY:-}"
  API_KEY="$(trim "$API_KEY")"
  local api_key_len=0

  if [[ -z "$API_KEY" ]]; then
    export API_KEY=""
    return
  fi

  api_key_len="${#API_KEY}"
  if (( api_key_len < MIN_API_KEY_LEN || api_key_len > MAX_API_KEY_LEN )); then
    echo "Invalid API_KEY length (${api_key_len}). Expected ${MIN_API_KEY_LEN}-${MAX_API_KEY_LEN} characters." >&2
    exit 1
  fi

  if [[ ! "$API_KEY" =~ $SAFE_API_KEY_REGEX ]]; then
    echo "Invalid API_KEY format. Refusing to start with malformed API key (whitespace/control chars are not allowed)." >&2
    exit 1
  fi

  export API_KEY
}

validate_tls_days() {
  local value="$1"
  local fallback="$2"

  if ! is_positive_int "$value"; then
    echo "Invalid TLS_DAYS='$value', using default ${fallback}" >&2
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

normalize_http_version_mode() {
  local raw="$1"
  local mode

  mode="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  mode="$(trim "$mode")"

  case "$mode" in
    auto|all|h1|h2|h3|h1+h2)
      printf '%s' "$mode"
      ;;
    http/1.1|http1|http1.1)
      printf 'h1'
      ;;
    http/2|http2)
      printf 'h2'
      ;;
    http/3|http3)
      printf 'h3'
      ;;
    *)
      echo "Invalid HTTP_VERSION_MODE='${raw}', using default ${DEFAULT_HTTP_VERSION_MODE}" >&2
      printf '%s' "$DEFAULT_HTTP_VERSION_MODE"
      ;;
  esac
}

haproxy_supports_quic() {
  # Build flag check (fast pre-filter)
  # Note: avoid pipe + grep -q with pipefail (SIGPIPE can cause false negatives)
  local vv_output
  vv_output="$(haproxy -vv 2>/dev/null)" || true
  if ! echo "$vv_output" | grep -Eiq 'USE_QUIC=1|[[:space:]]quic[[:space:]]: mode=HTTP'; then
    return 1
  fi

  # Runtime probe: verify QUIC bind actually works with the current SSL library
  local probe_dir probe_cfg probe_pem output
  probe_dir="$(mktemp -d)" || return 1
  probe_cfg="${probe_dir}/probe.cfg"
  probe_pem="${probe_dir}/probe.pem"

  if ! openssl req -x509 -newkey rsa:2048 -keyout "${probe_dir}/probe.key" -out "${probe_dir}/probe.crt" \
       -days 1 -nodes -subj "/CN=quic-probe" -batch 2>/dev/null; then
    rm -rf "$probe_dir"
    return 1
  fi
  cat "${probe_dir}/probe.crt" "${probe_dir}/probe.key" > "$probe_pem"

  printf 'global\n  log stderr format raw local0\ndefaults\n  mode http\n  timeout connect 5s\n  timeout client 5s\n  timeout server 5s\nfrontend quic_probe\n  bind quic4@*:65535 ssl crt %s alpn h3\n  default_backend quic_probe_be\nbackend quic_probe_be\n  server s1 127.0.0.1:1\n' \
      "$probe_pem" > "$probe_cfg"

  output="$(haproxy -c -f "$probe_cfg" 2>&1)" || true
  rm -rf "$probe_dir"

  if echo "$output" | grep -qi 'does not support the QUIC protocol'; then
    return 1
  fi
  return 0
}

resolve_listener_protocols() {
  local mode="$1"

  if ! is_true "$ENABLE_HTTPS"; then
    if [[ "$mode" != "h1" && "$mode" != "auto" ]]; then
      echo "HTTP_VERSION_MODE='${mode}' requested without TLS; falling back to HTTP/1.1" >&2
    fi

    BIND_PARAMS=""
    QUIC_BIND_LINE="# HTTP/3 disabled"
    EFFECTIVE_HTTP_VERSIONS="h1"
    return
  fi

  local alpn="http/1.1"
  local want_h3="false"

  case "$mode" in
    h1)
      alpn="http/1.1"
      ;;
    h2)
      alpn="h2"
      ;;
    h1+h2)
      alpn="h2,http/1.1"
      ;;
    h3)
      alpn="h2,http/1.1"
      want_h3="true"
      ;;
    auto|all)
      alpn="h2,http/1.1"
      want_h3="true"
      ;;
  esac

  BIND_PARAMS="ssl crt ${TLS_PEM_PATH} ssl-min-ver ${TLS_MIN_VERSION} alpn ${alpn}"
  EFFECTIVE_HTTP_VERSIONS="${alpn}"
  QUIC_BIND_LINE="# HTTP/3 disabled"

  if [[ "$want_h3" == "true" ]]; then
    if haproxy_supports_quic; then
      QUIC_BIND_LINE="bind quic4@*:${SERVER_PORT} ssl crt ${TLS_PEM_PATH} ssl-min-ver ${TLS_MIN_VERSION} alpn h3"
      EFFECTIVE_HTTP_VERSIONS="${EFFECTIVE_HTTP_VERSIONS},h3"
    else
      echo "HTTP_VERSION_MODE='${mode}' requested h3, but QUIC is not available in this HAProxy build; continuing with ${alpn}" >&2
    fi
  fi
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
    local escaped_key_sed
    escaped_key_sed="$(escape_sed_replacement "$API_KEY")"

    api_key_check="    # API Key authentication enabled (localhost /healthz excluded)
    acl auth_header_present var(txn.auth_header) -m found

    # Extract token: strip 'Bearer ' prefix (case-insensitive) into txn.api_token
    http-request set-var(txn.api_token) var(txn.auth_header),regsub(^[Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+,)

    # Validate extracted token via exact string match (no regex escaping issues)
    acl auth_valid var(txn.api_token) -m str ${escaped_key_sed}

    # Deny requests without valid authentication (except localhost health checks)
    http-request deny deny_status 401 content-type \"application/json\" string '{\"error\":\"Unauthorized\",\"message\":\"Valid API key required\"}' if !is_health_check !auth_header_present
    http-request deny deny_status 401 content-type \"application/json\" string '{\"error\":\"Unauthorized\",\"message\":\"Valid API key required\"}' if is_health_check !is_localhost !auth_header_present
    http-request deny deny_status 403 content-type \"application/json\" string '{\"error\":\"Forbidden\",\"message\":\"Invalid API key\"}' if !is_health_check auth_header_present !auth_valid
    http-request deny deny_status 403 content-type \"application/json\" string '{\"error\":\"Forbidden\",\"message\":\"Invalid API key\"}' if is_health_check !is_localhost auth_header_present !auth_valid"
  else
    api_key_check="    # API Key authentication disabled - all requests allowed"
  fi

  local escaped_bind_directive
    escaped_bind_directive="$(escape_sed_replacement "${BIND_PARAMS}")"
    local escaped_quic_bind_line
    escaped_quic_bind_line="$(escape_sed_replacement "${QUIC_BIND_LINE}")"

    sed -e "s|__SERVER_PORT__|${SERVER_PORT}|g" \
      -e "s|__BIND_PARAMS__|${escaped_bind_directive}|g" \
      -e "s|__QUIC_BIND_LINE__|${escaped_quic_bind_line}|g" \
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
  HTTP_VERSION_MODE="${HTTP_VERSION_MODE:-$DEFAULT_HTTP_VERSION_MODE}"

  SERVER_PORT="$(validate_port "SERVER_PORT" "$SERVER_PORT" "$DEFAULT_PORT")"
  INTERNAL_SERVER_PORT="$(validate_port "INTERNAL_SERVER_PORT" "$INTERNAL_SERVER_PORT" "$DEFAULT_INTERNAL_PORT")"
  TLS_DAYS="$(validate_tls_days "$TLS_DAYS" "$DEFAULT_TLS_DAYS")"
  TLS_MIN_VERSION="$(validate_tls_min_version "$TLS_MIN_VERSION" "$DEFAULT_TLS_MIN_VERSION")"
  HTTP_VERSION_MODE="$(normalize_http_version_mode "$HTTP_VERSION_MODE")"

  validate_api_key

  PUID="${PUID:-$DEFAULT_PUID}"
  PGID="${PGID:-$DEFAULT_PGID}"
  PUID="$(trim "$PUID")"
  PGID="$(trim "$PGID")"

  if [[ ! -f "$FIRST_RUN_FILE" ]]; then
    handle_first_run
  fi

  if is_true "$ENABLE_HTTPS"; then
    prepare_tls_pem "$TLS_CERT_PATH" "$TLS_KEY_PATH" "$TLS_PEM_PATH" "$TLS_DAYS" "$TLS_CN" "$TLS_SAN"
  fi

  resolve_listener_protocols "$HTTP_VERSION_MODE"

  generate_haproxy_config

  trap shutdown SIGINT SIGTERM EXIT

  start_server
  start_haproxy

  if [[ -n "$API_KEY" ]]; then
    echo "API key authentication enabled"
  else
    echo "API key authentication disabled"
  fi

  if is_true "$ENABLE_HTTPS"; then
    echo "HTTPS enabled on port ${SERVER_PORT}"
    echo "HTTP versions enabled: ${EFFECTIVE_HTTP_VERSIONS}"
  else
    echo "HTTPS disabled; serving HTTP on port ${SERVER_PORT}"
    echo "HTTP versions enabled: h1"
  fi

  wait -n "$SERVER_PID" "$HAPROXY_PID"
}

main "$@"
