# Portable WordPress environment

Self-contained Docker Compose environment for a clean WordPress installation,
targeted at 64-bit x86 servers (`linux/amd64`):

```text
Traefik -> Varnish -> NGINX -> PHP-FPM -> MySQL
                               |
                               +-------> Memcached
```

Only Traefik publishes a host port. All images are pulled from public Docker Hub
repositories. WordPress files and MySQL data are stored in named Docker volumes.

## Requirements

- Linux server with Docker Engine 24 or newer
- x86_64/AMD64 CPU; 32-bit x86 is not supported
- Docker Compose 2.20 or newer
- at least 2 GB RAM for a small installation
- ports 80/443 allowed by the server firewall as required

## Start locally

```bash
cp .env.example .env
```

Replace both MySQL passwords in `.env`, then run:

```bash
docker compose up -d --build --wait
```

Open <http://localhost:8080> and finish the standard WordPress installer.

## Start on a server

Set the public address in `.env` before starting:

```dotenv
COMPOSE_PROJECT_NAME=client-wordpress
DOCKER_PLATFORM=linux/amd64
SITE_HOST=wordpress.example.com
HTTP_PORT=80
WORDPRESS_URL=https://wordpress.example.com
```

`SITE_HOST` contains only the hostname or server IP. `WORDPRESS_URL` is the
complete visitor-facing URL without a trailing slash. The base stack serves
HTTP; terminate TLS at a load balancer or extend Traefik with ACME before using
the site in production. Forwarded HTTPS is already supported by WordPress.

Start and inspect the environment:

```bash
docker compose up -d --build --wait
docker compose ps
```

Stop it without removing persistent data:

```bash
docker compose down
```

Never use `docker compose down --volumes` unless the WordPress files and MySQL
database should be permanently deleted or have already been backed up.

## Health checks

- MySQL performs an authenticated `SELECT 1` against the WordPress database.
- Memcached sends a `version` command over TCP.
- `/livez.php` checks NGINX and PHP-FPM without depending on MySQL.
- `/healthz.php` checks NGINX, PHP-FPM, MySQL connectivity, and credentials.
- `/healthz` exposes the deep readiness check through Varnish and Traefik.
- Varnish checks both its process and the WordPress backend probe.
- Traefik uses its built-in ping endpoint.

For a future Kubernetes deployment, use `/livez.php` for liveness and
`/healthz.php` for readiness. A MySQL outage should make WordPress unready but
should not cause Kubernetes to restart an otherwise healthy PHP/NGINX process.

## Varnish

Varnish is the HTTP page-cache layer between Traefik and the WordPress NGINX
origin. It serves reusable anonymous responses from memory, reducing requests to
PHP-FPM and MySQL. Its configuration is stored in
`docker/varnish/default.vcl`, while the in-memory cache size is controlled by
`VARNISH_SIZE` in `.env` (`256M` by default).

The supplied VCL caches only `GET` and `HEAD` requests. A request bypasses the
cache when it contains an authorization header or matches one of these cases:

- WordPress login, admin, cron, comment, activation, REST API, or XML-RPC paths
- preview, search, add-to-cart, WooCommerce API, and similar query parameters
- logged-in WordPress, password-protected post, comment-author, or WooCommerce
  cookies
- responses that set cookies, return a server error, explicitly disable cache,
  or have no positive TTL

Cacheable responses respect their upstream cache lifetime, capped at 10 minutes.
Cached objects have a one-hour grace window, allowing Varnish to temporarily
serve stale content if the WordPress origin becomes unavailable. The health
endpoint is always passed to WordPress and is never served from cache.

Every response passing through Varnish includes an `X-Cache` header:

- `X-Cache: MISS` means the response came from WordPress or was not cacheable.
- `X-Cache: HIT` means Varnish served an existing cached object.

Request the same anonymous page twice to inspect cache behavior:

```bash
curl -I https://wordpress.example.com/
curl -I https://wordpress.example.com/
```

Some WordPress responses intentionally remain `MISS`, for example the installer,
admin pages, logged-in sessions, and responses containing `Set-Cookie` or
`Cache-Control: no-cache`.

### Purging cached content

`PURGE` and `BAN` requests are restricted to the internal application network.
A WordPress cache-purge plugin can therefore invalidate content without exposing
cache administration publicly. To purge one URL manually, run the request from
the WordPress container and provide the public host header:

```bash
docker compose exec wordpress curl -i -X PURGE \
  -H 'Host: wordpress.example.com' \
  http://varnish/example-page/
```

To invalidate the complete cache using the Varnish administration interface:

```bash
docker compose exec varnish varnishadm 'ban req.url ~ .'
```

After editing `docker/varnish/default.vcl`, validate and reload it without
rebuilding the image:

```bash
docker compose exec varnish varnishd -C -f /etc/varnish/default.vcl
docker compose exec varnish varnishreload
```

Inspect backend health and cache statistics with:

```bash
docker compose exec varnish varnishadm backend.list
docker compose exec varnish varnishstat -1
```

The included rules are safe general WordPress defaults, but caching must be
reviewed when adding e-commerce, membership, personalization, multilingual, or
other plugins that introduce session-specific cookies and URLs.

## Memcached

The WordPress image contains the PHP `memcached` extension and the server address
`memcached:11211`. WordPress core does not use object caching automatically;
install a compatible object-cache plugin/drop-in during WordPress setup.

## Backups

Back up both named volumes: the MySQL database and the complete WordPress tree.
Database dump example:

```bash
docker compose exec -T db sh -c \
  'MYSQL_PWD="$MYSQL_PASSWORD" mysqldump -u "$MYSQL_USER" "$MYSQL_DATABASE"' \
  > wordpress.sql
```

Files placed in `docker/mysql/init/` run only when MySQL initializes an empty
database volume. Changing passwords in `.env` later does not update accounts in
an existing database volume.
