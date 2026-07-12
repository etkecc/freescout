# FreeScout (docker image)

A first-party [FreeScout](https://freescout.net) image: pinned Alpine, an explicit PHP extension set, and a single container supervised by `s6-svscan`. It runs fully unprivileged and streams every log to stdout/stderr.

Published as `ghcr.io/etkecc/freescout:v<freescout-version>` (for example `v1.8.212`). The tag carries the FreeScout release; the PHP version is an internal detail and is not part of the tag.

## What runs inside

This is a persistent worker, not just a web server: alongside serving the UI it keeps the helpdesk alive between requests. If the scheduler stops, time-based automations freeze; if the queue worker stops, incoming and outgoing mail stops flowing.

`s6-svscan` is PID 1 and supervises four processes as one uid:

- `nginx` on port 8080, fronting
- `php-fpm` over a unix socket
- the scheduler (`schedule:run` every minute), which drives the time-based automations
- the queue worker (`queue:work` over the `emails` and `default` queues), which delivers and fetches mail

nginx waits for the php-fpm socket before it accepts connections, so a fresh container never answers with a 502.

## Environment

The image reads the env vars. Values are translated to Laravel's own names in process env at boot; only `APP_KEY` is persisted to disk.

| Variable | Meaning |
|---|---|
| `SITE_URL` | Public URL, becomes `APP_URL` |
| `TZ` | Timezone |
| `APPLICATION_NAME` | UI name |
| `DB_TYPE` | `mysql` or `pgsql` |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS` | Database connection |
| `DB_PGSQL_SSL_MODE` | Postgres SSL mode |
| `ADMIN_EMAIL`, `ADMIN_PASS` | Bootstrap admin, created once on an empty database |
| `CONTAINER_LOG_LEVEL` | `DEBUG`/`INFO`/`NOTICE`/`WARN` |
| `DISPLAY_ERRORS` | `TRUE`/`FALSE` |

Any variable Laravel reads natively (for example `APP_TRUSTED_HOSTS`) is passed straight through: set it in the container env and the app picks it up via `getenv()`. It is never written to a file, so it cannot be dropped on a restart.

## Storage

One volume, `/data`, holds everything the app writes: attachments, sessions, installed modules, and the persisted `APP_KEY` (in `/data/config`). The application tree itself is read-only; every writable path is a symlink into `/data`.

`/data` must be owned by the uid the container runs as. The image does not chown anything: if it cannot write `/data` it exits with a clear message rather than booting half-broken.

## Logs

Everything goes to the container streams. nginx access on stdout, nginx and PHP errors on stderr. There is no log file and no log volume; use `docker logs` or journald.

## Modules

Install modules from the FreeScout admin UI. They land in `/data/Modules` and persist across restarts; their public asset symlinks are rebuilt on every boot.

There is no build toolchain in the image (no Node), so a module that ships only source and needs a webpack step is unsupported. Modules that ship prebuilt assets, which is the common case, work.

## PHP 8.3

The image pins PHP 8.3 on purpose. FreeScout fetches support mail over `ext-imap`, and PHP 8.4 moved that extension to an unmaintained PECL package that Alpine does not ship. `php83-imap` is a clean, packaged extension, so 8.3 keeps the mail path whole. The line moves forward once FreeScout adopts a maintained IMAP library or Alpine packages a newer `imap`.

## Build

```sh
just build              # builds v1.8.212
just build 1.8.229      # builds a specific version
just lint               # hadolint + shellcheck
```
