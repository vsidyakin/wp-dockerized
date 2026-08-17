#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" != "wordpress-nginx" ]]; then
    exec /usr/local/bin/docker-entrypoint.sh "$@"
fi

# Populate/upgrade /var/www/html and generate wp-config.php using the official
# WordPress entrypoint, but return here before starting PHP-FPM.
/usr/local/bin/docker-entrypoint.sh php-fpm -t

install -o www-data -g www-data -m 0644 \
    /usr/local/share/wordpress/livez.php \
    /var/www/html/livez.php

install -o www-data -g www-data -m 0644 \
    /usr/local/share/wordpress/healthz.php \
    /var/www/html/healthz.php

nginx -t

php-fpm -F &
php_fpm_pid=$!

nginx -g 'daemon off;' &
nginx_pid=$!

shutdown() {
    trap - TERM INT QUIT

    if kill -0 "$nginx_pid" 2>/dev/null; then
        kill -QUIT "$nginx_pid" 2>/dev/null || true
    fi
    if kill -0 "$php_fpm_pid" 2>/dev/null; then
        kill -TERM "$php_fpm_pid" 2>/dev/null || true
    fi

    wait "$nginx_pid" 2>/dev/null || true
    wait "$php_fpm_pid" 2>/dev/null || true
}

trap shutdown TERM INT QUIT

set +e
wait -n "$php_fpm_pid" "$nginx_pid"
status=$?
set -e

shutdown
exit "$status"
