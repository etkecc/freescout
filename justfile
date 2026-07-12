# show help by default
default:
    @just --list --justfile {{ justfile() }}

# lint the Dockerfile and shell scripts
lint:
    shellcheck rootfs/entrypoint.sh rootfs/usr/local/bin/*.sh rootfs/etc/s6/services/*/run

# build the image locally for the given FreeScout version
build version:
    docker build --build-arg FREESCOUT_VERSION={{ version }} -t ghcr.io/etkecc/freescout:v{{ version }} .
