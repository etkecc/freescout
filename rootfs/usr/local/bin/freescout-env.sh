#!/bin/sh
# Translate configuration env vars into Laravel-native process env, and seed
# APP_KEY once. Sourced by entrypoint.sh so exports reach every s6 service.
# Laravel env() reads getenv() before .env; /data/config (the .env file) is
# seeded with APP_KEY on first boot, then owned by FreeScout, which persists
# dashboard settings (2FA policy, etc.) there.
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

# Seed APP_KEY once, on first boot only. After that FreeScout owns /data/config:
# it writes dashboard settings (2FA policy, etc.) there, so rewriting the file
# would destroy them. An existing file without APP_KEY is left untouched on
# purpose: minting a new key would make already-encrypted data undecryptable, so
# we let FreeScout fail loudly rather than silently corrupt.
if [ ! -f /data/config ]; then
  ( umask 077; printf 'APP_KEY=base64:%s\n' "$(head -c 32 /dev/urandom | base64)" > /data/config )
fi
