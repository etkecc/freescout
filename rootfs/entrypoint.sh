#!/bin/sh
set -eu

WEBROOT=/var/www/html
DATA=/data

if ! ( umask 022; : > "$DATA/.writetest" ) 2>/dev/null; then
  echo "FATAL: /data is not writable by uid $(id -u):$(id -g). Chown it before starting the container." >&2
  exit 1
fi
rm -f "$DATA/.writetest"

# shellcheck source=/dev/null  # resolved at runtime; linted on its own in CI
. /usr/local/bin/freescout-env.sh

mkdir -p "$DATA/storage/framework/cache/data" \
         "$DATA/storage/framework/sessions" \
         "$DATA/storage/framework/views" \
         "$DATA/storage/logs" \
         "$DATA/storage/app/public" \
         "$DATA/storage/debugbar" \
         "$DATA/Modules" \
         /tmp/bootstrap-cache /tmp/public-modules /tmp/gen

if [ -z "$(ls -A "$DATA/Modules" 2>/dev/null)" ]; then
  tar -C "$WEBROOT/.skel-modules" -cf - . | tar -C "$DATA/Modules" -xf -
fi

php artisan migrate --force
if [ -n "${ADMIN_EMAIL:-}" ] && [ -n "${ADMIN_PASS:-}" ]; then
  # $-vars are PHP, not shell; single quotes are intentional
  # shellcheck disable=SC2016
  users=$(php -r 'require "/var/www/html/vendor/autoload.php"; $a = require "/var/www/html/bootstrap/app.php"; $a->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap(); try { echo \App\User::count(); } catch (\Throwable $e) { echo "-1"; }' 2>/dev/null)
  if [ "$users" = "0" ]; then
    php artisan freescout:create-user -n --role=admin \
      --firstName="${ADMIN_FIRST_NAME:-Admin}" --lastName="${ADMIN_LAST_NAME:-User}" \
      --email="$ADMIN_EMAIL" --password="$ADMIN_PASS" || true
  fi
fi

# $-vars are PHP, not shell; single quotes are intentional
# shellcheck disable=SC2016
php -r 'require "/var/www/html/vendor/autoload.php"; $a = require "/var/www/html/bootstrap/app.php"; $a->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap(); \Module::clearCache(); foreach (\Module::all() as $m) { try { \Artisan::call("freescout:module-install", ["module_alias" => $m->getAlias(), "--no-interaction" => true]); $o = \Artisan::output(); if (stripos($o, "error") !== false || stripos($o, "not found") !== false) { fwrite(STDERR, "WARN: module ".$m->getAlias()." install reported: ".trim($o)."\n"); } } catch (\Throwable $e) { fwrite(STDERR, "WARN: module ".$m->getAlias()." install threw: ".$e->getMessage()."\n"); } }' || true
php artisan freescout:build -n
php artisan cache:clear -n 2>/dev/null || true
php artisan view:clear -n 2>/dev/null || true

cp -r /etc/s6/services /tmp/s6
exec s6-svscan /tmp/s6
