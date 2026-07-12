#!/bin/sh
# Translate env vars into Laravel-native process env, and
# persist APP_KEY exactly once. Sourced by entrypoint.sh so exports reach every
# s6 service. Laravel env() reads getenv() before .env, so the only file we own
# is /data/config, and it holds nothing but APP_KEY.
set -eu

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

export APP_URL="${SITE_URL:-}"
export APP_NAME="${APPLICATION_NAME:-FreeScout}"
export APP_TIMEZONE="${TZ:-UTC}"
export APP_LOG=errorlog

case "$(lower "${CONTAINER_LOG_LEVEL:-INFO}")" in
  debug)  export APP_LOG_LEVEL=debug ;;
  notice) export APP_LOG_LEVEL=notice ;;
  warn|warning) export APP_LOG_LEVEL=warning ;;
  *)      export APP_LOG_LEVEL=info ;;
esac

case "$(lower "${DISPLAY_ERRORS:-false}")" in
  true|1) export APP_DEBUG=true ;;
  *)      export APP_DEBUG=false ;;
esac

export DB_CONNECTION="${DB_TYPE:-}"
export DB_DATABASE="${DB_NAME:-}"
export DB_USERNAME="${DB_USER:-}"
export DB_PASSWORD="${DB_PASS:-}"

[ -n "${DB_PGSQL_SSL_MODE:-}" ] && export DB_PGSQL_SSLMODE="$DB_PGSQL_SSL_MODE"

needs_rewrite=1
if [ -f /data/config ] && [ "$(grep -cE '[^[:space:]]' /data/config)" = "1" ] && grep -q '^APP_KEY=' /data/config; then
  needs_rewrite=0
fi
if [ "$needs_rewrite" = 1 ]; then
  key=$(grep -m1 '^APP_KEY=' /data/config 2>/dev/null | cut -d= -f2-)
  [ -z "$key" ] && key="base64:$(head -c 32 /dev/urandom | base64)"
  if [ -f /data/config ]; then
    cp -f /data/config /data/config.legacy 2>/dev/null || true
  fi
  tmp="$(mktemp /data/config.XXXXXX)"
  ( umask 077; printf 'APP_KEY=%s\n' "$key" > "$tmp" )
  mv -f "$tmp" /data/config
fi
