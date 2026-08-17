# syntax=docker/dockerfile:1

ARG WORDPRESS_IMAGE=wordpress:7.0.2-php8.3-fpm
FROM ${WORDPRESS_IMAGE}

ARG MEMCACHED_PHP_VERSION=3.3.0

# Add NGINX and the PHP Memcached client to the official WordPress FPM image.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        $PHPIZE_DEPS \
        curl \
        libmemcached-dev \
        libsasl2-dev \
        libzstd-dev \
        nginx \
        zlib1g-dev; \
    pecl install "memcached-${MEMCACHED_PHP_VERSION}"; \
    docker-php-ext-enable memcached; \
    apt-get purge -y --auto-remove $PHPIZE_DEPS; \
    rm -rf /tmp/pear /var/lib/apt/lists/*

RUN rm -f /etc/nginx/sites-enabled/default \
    && mkdir -p /run/nginx

COPY docker/wordpress/nginx.conf /etc/nginx/nginx.conf
COPY docker/wordpress/wordpress.ini $PHP_INI_DIR/conf.d/wordpress.ini
COPY docker/wordpress/livez.php /usr/local/share/wordpress/livez.php
COPY docker/wordpress/healthz.php /usr/local/share/wordpress/healthz.php
COPY docker/wordpress/entrypoint-wrapper.sh /usr/local/bin/wordpress-entrypoint-wrapper

RUN chmod 0755 /usr/local/bin/wordpress-entrypoint-wrapper

ENTRYPOINT ["wordpress-entrypoint-wrapper"]
CMD ["wordpress-nginx"]

HEALTHCHECK --interval=10s --timeout=5s --start-period=40s --retries=6 \
    CMD curl --fail --silent --show-error --max-time 4 http://127.0.0.1/healthz.php > /dev/null || exit 1
