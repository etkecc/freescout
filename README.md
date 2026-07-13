# FreeScout (docker image)

Most self-hosted FreeScout images run as root, write their logs to a file nobody rotates until the disk fills, and fall over the moment you point a read-only filesystem at them. This one is built the other way around. It runs as an unprivileged user with zero Linux capabilities. It boots happily under `--read-only` and streams every log line straight to `docker logs`. If you run a tight ship, it won't fight you.

Published as `ghcr.io/etkecc/freescout:v<freescout-version>` (for example `v1.8.229`), for `linux/amd64` and `linux/arm64`. The tag is the FreeScout release; the PHP version is an internal detail and stays out of the tag.

## Built for the day it gets popped

FreeScout is a Laravel app that runs modules you install from a web UI and takes file uploads from people you have never met. That is a generous number of ways in. So the image assumes the app gets compromised one day and works to make that day boring:

- **Never root.** Every process runs as one unprivileged uid (10001 by default). nginx listens on 8080, an unprivileged port, so it never needed a bind capability in the first place.
- **No capabilities, no way up.** It runs clean under `--cap-drop=ALL` and asks for nothing back, and `--security-opt=no-new-privileges` holds because there is not one setuid binary in the image to climb.
- **Read-only rootfs.** The application tree is immutable. A webshell that writes itself to disk lands on a tmpfs that evaporates on the next restart, and the code it wanted to edit is read-only anyway.

The only writable surfaces are one tmpfs at `/tmp` and your `/data` volume. That is the whole blast radius.

## Logs go where logs go

nginx access on stdout, nginx and PHP errors on stderr, php-fpm straight to the master's stderr. No log file, no log volume, no logrotate you set up six months ago and forgot until the disk filled at 3am. Point `docker logs` or journald at it.

## Settings that survive a restart

FreeScout writes some of its own configuration back to disk: flip on 2FA enforcement in the admin panel and it saves that into the app's `.env`, which this image keeps at `/data/config`. The image writes `APP_KEY` into that file exactly once, on the first boot into an empty `/data`, and then forgets it exists. FreeScout owns the file from there. That part is deliberate: plenty of container setups rewrite the `.env` on every boot and quietly erase whatever you last changed in the panel.

Everything else is plain env vars, mapped to Laravel's own names in process env at boot and read through `getenv()`, so a restart has no file to drop them from:

| Variable | Meaning |
|---|---|
| `SITE_URL` | Public URL, becomes `APP_URL` |
| `TZ` | Timezone |
| `APPLICATION_NAME` | UI name |
| `DB_TYPE` | `mysql` or `pgsql` |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS` | Database connection |
| `DB_PGSQL_SSL_MODE` | Postgres SSL mode |
| `ADMIN_EMAIL`, `ADMIN_PASS` | Bootstrap admin, created once on an empty database |
| `CONTAINER_LOG_LEVEL` | `DEBUG` / `INFO` / `NOTICE` / `WARN` |
| `DISPLAY_ERRORS` | `TRUE` / `FALSE` |

Anything Laravel reads natively (say `APP_TRUSTED_HOSTS`) rides straight through: set it in the container env and the app picks it up.

## One volume holds the state

`/data` is everything the app keeps: attachments, sessions, installed modules, and the `APP_KEY`. The application tree ships read-only and every writable path inside it is a symlink into `/data` or the tmpfs. Back up `/data` and you have backed up the helpdesk.

`/data` has to be owned by the uid the container runs as. The image chowns nothing on its own: it writes a probe file to `/data` on boot, and if that write fails it says so and exits, instead of booting half-broken and leaving you to work out later why attachments keep vanishing.

## What actually runs inside

This is a persistent worker, not just a web server. `s6-svscan` is PID 1 and supervises four processes as one uid:

- `nginx` on 8080, fronting
- `php-fpm` over a unix socket
- the scheduler (`schedule:run` every minute), which drives every time-based automation
- the queue worker (`queue:work` on the `emails` and `default` queues), which sends and fetches mail

Let the scheduler die and time-based automations freeze. The queue worker matters as much: without it, mail stops moving. Both run under supervision for exactly that reason. nginx also waits for the php-fpm socket before it takes a connection, so a cold container never greets you with a 502. A built-in healthcheck reports the same readiness to your orchestrator.

## Running it

The image wants a database and a writable `/data`. Locked down, it looks like this:

```sh
docker run -d --name freescout \
  --user 10001:10001 \
  --cap-drop=ALL \
  --security-opt=no-new-privileges:true \
  --read-only \
  --tmpfs /tmp:rw,exec,nosuid,size=512m \
  -v /srv/freescout/data:/data \
  -e SITE_URL=https://help.example.com \
  -e DB_TYPE=pgsql \
  -e DB_HOST=db -e DB_NAME=freescout -e DB_USER=freescout -e DB_PASS=secret \
  -e ADMIN_EMAIL=you@example.com -e ADMIN_PASS=changeme \
  ghcr.io/etkecc/freescout:v1.8.229
```

> **The `/tmp` tmpfs has to allow `exec`.** s6 runs its service scripts out of `/tmp/s6`, so the reflex `noexec` you slap on `/tmp` everywhere else will kill this container on boot. Everything else about `/tmp` is happy with the defaults.

For a production deployment with Traefik, a managed database, backups, and upgrades wired together, use the etke.cc FreeScout role for the MASH Ansible playbook.

## Modules

Install modules from the FreeScout admin UI. They land in `/data/Modules` and survive restarts; their public asset symlinks get rebuilt on every boot. A module that needs a build step will not work, because there is no toolchain in the image (no Node, no webpack). Most modules ship prebuilt assets and just run; if yours ships only source, build it outside and mount the result into `/data/Modules`.

## Why PHP 8.3

Pinned on purpose, and not because we love 8.3. FreeScout pulls support mail over `ext-imap`, and PHP 8.4 kicked that extension out to an unmaintained PECL package Alpine does not ship. Chasing the newer runtime means breaking the mail path, so we stay on 8.3, where `php83-imap` is a clean, packaged extension that keeps mail whole. The pin moves forward the day FreeScout adopts a maintained IMAP library or Alpine packages a newer `imap`, and not a day sooner.

## Build

```sh
just build 1.8.229      # build the image for a FreeScout version
just lint               # shellcheck the entrypoint and service scripts
```
