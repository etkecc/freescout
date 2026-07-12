# syntax=docker/dockerfile:1

#######################################
# Stage 1: build (composer + assets)  #
#######################################

FROM alpine:3.24.1 AS build

ARG FREESCOUT_VERSION
# renovate: datasource=github-releases depName=composer/composer
ARG COMPOSER_VERSION=2.10.2

# The alpine `composer` package pulls the DEFAULT php (php85), which lacks our
# php83 extensions; so php83 is the only interpreter and composer is a pinned phar.
RUN apk add --no-cache \
      curl \
      git \
      php83 \
      php83-fpm \
      php83-ctype \
      php83-curl \
      php83-dom \
      php83-fileinfo \
      php83-gd \
      php83-iconv \
      php83-imap \
      php83-intl \
      php83-ldap \
      php83-mbstring \
      php83-opcache \
      php83-openssl \
      php83-pcntl \
      php83-pdo \
      php83-pdo_mysql \
      php83-pdo_pgsql \
      php83-pecl-igbinary \
      php83-phar \
      php83-posix \
      php83-session \
      php83-simplexml \
      php83-tokenizer \
      php83-xml \
      php83-xmlreader \
      php83-xmlwriter \
      php83-zip \
 && ln -sf /usr/bin/php83 /usr/bin/php \
 && curl -fsSL "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar" -o /usr/local/bin/composer \
 && chmod +x /usr/local/bin/composer

WORKDIR /app

RUN curl -fsSL "https://github.com/freescout-helpdesk/freescout/archive/refs/tags/${FREESCOUT_VERSION}.tar.gz" \
      | tar -xz --strip-components=1

RUN composer install --no-dev --no-interaction --no-progress --no-autoloader \
      --ignore-platform-req=php+ \
 && mkdir -p \
      vendor/rap2hpoutre/laravel-log-viewer/src/controllers \
      vendor/natxet/cssmin/src \
 && composer dump-autoload --no-dev --ignore-platform-req=php+

# freescout:build = generate-vars + laroute:generate, both PHP-only, no DB.
# APP_KEY is supplied transiently so the framework boots; it is never persisted.
RUN APP_KEY="base64:$(head -c32 /dev/urandom | base64)" php artisan freescout:build

#######################################
# Stage 2: runtime                    #
#######################################

FROM alpine:3.24.1

RUN apk add --no-cache \
      curl \
      libcap \
      nginx \
      s6 \
      php83 \
      php83-fpm \
      php83-ctype \
      php83-curl \
      php83-dom \
      php83-fileinfo \
      php83-gd \
      php83-iconv \
      php83-imap \
      php83-intl \
      php83-ldap \
      php83-mbstring \
      php83-opcache \
      php83-openssl \
      php83-pcntl \
      php83-pdo \
      php83-pdo_mysql \
      php83-pdo_pgsql \
      php83-pecl-igbinary \
      php83-phar \
      php83-posix \
      php83-session \
      php83-simplexml \
      php83-tokenizer \
      php83-xml \
      php83-xmlreader \
      php83-xmlwriter \
      php83-zip \
 && ln -sf /usr/bin/php83 /usr/bin/php \
 && setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx \
 && rm -rf /var/cache/apk/* /etc/nginx/http.d/default.conf

RUN addgroup -g 10001 freescout \
 && adduser -D -H -u 10001 -G freescout freescout

COPY --from=build /app /var/www/html

RUN set -eux; \
    mv /var/www/html/storage /var/www/html/.skel-storage; \
    mv /var/www/html/Modules /var/www/html/.skel-modules; \
    rm -rf /var/www/html/bootstrap/cache \
           /var/www/html/public/storage \
           /var/www/html/public/modules \
           /var/www/html/public/js/laroute.js; \
    ln -s /data/storage            /var/www/html/storage; \
    ln -s /data/Modules            /var/www/html/Modules; \
    ln -s /data/config             /var/www/html/.env; \
    ln -s /data/storage/app/public /var/www/html/public/storage; \
    ln -s /tmp/bootstrap-cache     /var/www/html/bootstrap/cache; \
    ln -s /tmp/public-modules      /var/www/html/public/modules; \
    ln -s /tmp/gen/laroute.js      /var/www/html/public/js/laroute.js

COPY rootfs/ /

RUN chmod +x /entrypoint.sh /usr/local/bin/freescout-env.sh /etc/s6/services/*/run

WORKDIR /var/www/html

USER freescout

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD sh -c 'c=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/ 2>/dev/null); case "$c" in 000|502|503|504) exit 1;; *) exit 0;; esac'

ENTRYPOINT ["/entrypoint.sh"]
