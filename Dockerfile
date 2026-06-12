# ================================
# Stage: PHP Base
# ================================
FROM --platform=$TARGETOS/$TARGETARCH php:8.5-fpm-alpine AS base-php

ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN install-php-extensions bcmath gd intl zip opcache pcntl posix pdo_mysql pdo_pgsql \
    && rm /usr/local/bin/install-php-extensions

# ================================
# Stage: Composer
# ================================
FROM --platform=$TARGETOS/$TARGETARCH base-php AS composer

WORKDIR /build

COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
COPY composer.json composer.lock ./

RUN composer install --no-dev --no-interaction --no-autoloader --no-scripts

COPY --exclude=nginx.conf --exclude=docker/ . ./
RUN composer dump-autoload --optimize --no-scripts

# ================================
# Stage: NPM / Frontend
# ================================
FROM --platform=$TARGETOS/$TARGETARCH node:alpine AS npm

WORKDIR /build

COPY package.json package-lock.json ./
RUN npm ci

COPY --exclude=nginx.conf --exclude=docker/ . ./
COPY --from=composer /build/vendor ./vendor

RUN npm run build

# ================================
# Stage: Final
# ================================
FROM --platform=$TARGETOS/$TARGETARCH base-php AS final

WORKDIR /var/www/html

RUN apk add --no-cache nginx ca-certificates supervisor supercronic fcgi

COPY --chown=root:www-data --chmod=640 --from=composer /build .
COPY --chown=root:www-data --chmod=640 --from=npm /build/public ./public

RUN chown root:www-data ./ \
    && chmod 750 ./ \
    && find ./ -type d -exec chmod 750 {} \; \
    && mkdir -p \
        /laravel_template-data/storage \
        /var/www/html/storage/app/public \
        /var/run/supervisord \
        /etc/supercronic \
        /var/lib/nginx/tmp/client_body \
        /var/lib/nginx/logs \
        /var/log/nginx \
        /run/nginx \
    && ln -s /laravel_template-data/.env ./.env \
    && ln -s /laravel_template-data/database/database.sqlite ./database/database.sqlite \
    && ln -sf /var/www/html/storage/app/public /var/www/html/public/storage \
    && ln -s /laravel_template-data/storage/avatars /var/www/html/storage/app/public/avatars \
    && ln -s /laravel_template-data/storage/fonts /var/www/html/storage/app/public/fonts \
    && chown -R www-data:www-data \
        /laravel_template-data \
        ./storage \
        ./bootstrap/cache \
        /var/run/supervisord \
        /var/lib/nginx \
        /var/log/nginx \
        /run/nginx \
        /var/www/html/public/storage \
    && chmod -R u+rwX,g+rwX,o-rwx \
        /laravel_template-data \
        ./storage \
        ./bootstrap/cache \
        /var/run/supervisord \
        /var/lib/nginx \
        /var/log/nginx \
        /run/nginx \
    && chown -R www-data: /usr/local/etc/php/

COPY docker/supervisord.conf /etc/supervisord.conf
COPY docker/nginx.conf /etc/nginx/http.d/default.conf
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/healthcheck.sh /healthcheck.sh

HEALTHCHECK --interval=5m --timeout=10s --start-period=5s --retries=3 \
    CMD /bin/ash /healthcheck.sh

EXPOSE 80 443
VOLUME /laravel_template-data
USER www-data

ENTRYPOINT ["/bin/ash", "/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisord.conf"]