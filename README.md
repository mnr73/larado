# Larado

Docker setup for Laravel on top of [serversideup/php](https://serversideup.net/open-source/docker-php/) (`fpm-nginx`). Three files are copied into the project. `docker compose up -d --build` starts everything.

## What it runs

| Service | Role |
|---|---|
| `app` | nginx + PHP-FPM. Runs migrations at start (`AUTORUN_ENABLED`), plus the Laravel caches in production. |
| `queue` | `queue:work`, `QUEUE_REPLICAS` copies (default 2), with a healthcheck. |
| `scheduler` | `schedule:work`, with a healthcheck. |
| `mysql` | MySQL 8.4. Settings: `larado/mysql.cnf`. |
| `redis` | Redis 7. Settings: `larado/redis.conf`. |
| `phpmyadmin` | Dev only. |

Extensions: the image ships with `pcntl`, `redis`, `zip`, `pdo_mysql` and `opcache`. `Dockerfile` adds `gd intl exif sockets mysqli`. The `dev` stage also adds `xdebug`.

## Install

In the root of a Laravel project:

```sh
curl -fsSL https://raw.githubusercontent.com/mnr73/larado/main/install.sh | sh
```

This downloads `Dockerfile`, `compose.yml`, `compose.dev.yml` and `larado/mysql.cnf` + `larado/redis.conf` (these two are never overwritten once they exist), and appends the larado variables from `.env.larado.example` to `.env`. It never touches an existing `LARADO_IMAGE`.

Then set the hosts in `.env`:

```env
DB_HOST=mysql
REDIS_HOST=redis
DB_PASSWORD=...        # required, also becomes the mysql root password
```

```sh
docker compose up -d --build
```

## Dev and prod

`compose.yml` is production. `compose.dev.yml` is for local use only. It builds the `dev` target and adds xdebug, phpMyAdmin and the published db/redis ports.

It is switched on by one line in `.env`:

```env
COMPOSE_FILE=compose.yml:compose.dev.yml
```

- **Local:** keep that line.
- **Server:** leave it out. Compose then reads only `compose.yml`. `compose.dev.yml` can stay in git.

The file is deliberately not called `compose.override.yml`, because Compose merges that name automatically.

## Environment variables

| Variable | Default | Notes |
|---|---|---|
| `PHP_VERSION` | `8.4` | Build arg for the base image tag. |
| `LARADO_IMAGE` | `larado` | Image name, shared by all projects. Tags are `:prod` and `:dev`. Must be lowercase. |
| `APP_PORT` | `8000` | Host port of the web server (nginx listens on 8080 in the container). |
| `QUEUE_REPLICAS` | `2` | Number of queue workers. |
| `PHP_MEMORY_LIMIT` | `512M` | |
| `FORWARD_DB_PORT` | `3306` | Dev only. Not `DB_PORT`, because Laravel reads that. |
| `FORWARD_REDIS_PORT` | `6379` | Dev only. |
| `PMA_PORT` | `8080` | Dev only. |
| `XDEBUG_MODE` | `off` | Dev only. `debug` turns on step debugging (see [Xdebug](#xdebug)). |
| `PUID` / `PGID` | `1000` | Dev only. Build-time user id of `www-data`. |

Any other `PHP_*` or `NGINX_*` setting works as an env var; see the [variable reference](https://serversideup.net/open-source/docker-php/docs/reference/environment-variable-specification).

## MySQL and Redis settings

`larado/mysql.cnf` and `larado/redis.conf` are mounted read-only into the containers. Every setting is commented out, so the server defaults apply. Uncomment or add what you need and restart:

```sh
docker compose restart mysql   # or redis
```

No image build is needed. Check a value, e.g. `docker compose exec mysql mysql -uroot -p -e "select @@max_connections"`.

Redis starts with `redis-server /usr/local/etc/redis/redis.conf`, so settings must go in that file, not in `command`. Note that `stop-writes-on-bgsave-error no` is commented out: with the default (`yes`), Redis refuses writes when a snapshot fails, which stops queues and cache.

## Xdebug

Installed in the dev image but **off by default**, because it slows every request. To debug:

1. In `.env` set `XDEBUG_MODE=debug`, then `docker compose up -d` (no build needed).
2. In the IDE listen on port `9003` and map the project root to `/var/www/html`.
3. Xdebug starts only for requests that carry the trigger (`start_with_request=trigger`): use a browser extension such as "Xdebug helper", or add `?XDEBUG_TRIGGER=1` to the URL / `XDEBUG_TRIGGER=1` cookie. For CLI: `docker compose exec -e XDEBUG_TRIGGER=1 app php artisan ...`.
4. When done, set `XDEBUG_MODE=off` again and `docker compose up -d`.

Want every request debugged instead? Set `XDEBUG_CONFIG` on the service with `start_with_request=yes`. `develop` mode (nicer error output) also costs time on every request.

## Dev speed

`compose.dev.yml` keeps OPcache on with `validate_timestamps=1, revalidate_freq=0`: changed files are recompiled on the next request, the rest stays cached. Measured on a Laravel + Filament API: 300-450ms per request with OPcache off and xdebug on, 30-50ms with these defaults.

Dev does not run `optimize` on start. Cached config would make `php artisan test` use your real `.env` instead of `phpunit.xml`, and new routes would 404 until `php artisan optimize:clear`.

## File ownership

serversideup images have **no runtime PUID/PGID**. The container runs as `www-data` (33:33). Setting `user:` in compose breaks nginx, which then cannot write `/etc/nginx`.

- **Dev:** the `dev` stage changes `www-data` to `PUID:PGID` at build time, so files in `storage/` match your host user. If you change those values, run `docker compose build`.
- **Prod:** `www-data` stays 33. On the server, give it write access to `storage` and `bootstrap/cache`:
  `sudo chown -R 33:33 storage bootstrap/cache`

## Frontend (npm on the host, php in the container)

Node runs on the host, PHP runs in the container. Tools that call `php artisan` from node fail with `Command failed: php artisan ...`. For Wayfinder, set the command in `vite.config.ts`:

```ts
wayfinder({
    formVariants: true,
    command: 'docker compose exec -T app php artisan wayfinder:generate',
}),
```

A `500 Vite manifest not found` with healthy containers means the frontend isn't built yet: run `npm run build` or `npm run dev`.

## Production notes

- Run only `compose.yml` (no `COMPOSE_FILE` in the server `.env`).
- Behind a reverse proxy, set `TRUSTED_PROXIES` on `app`. See the [docs](https://serversideup.net/open-source/docker-php/docs/deployment-and-production/configuring-trusted-proxies).
- `AUTORUN_ENABLED` is set on `app` only. Setting it on a worker makes it migrate on start.
- Production OPcache does not check file times (`validate_timestamps=0`) and the code is bind-mounted: after deploying new code run `docker compose up -d --force-recreate` (or `restart app queue scheduler`), otherwise the old code keeps running.
- Workers use `stop_signal: SIGTERM`. The image default is `SIGQUIT`, which Laravel workers ignore. `stop_grace_period` is 60s; raise it for long jobs.
- Use Horizon instead of `queue`? Replace the `queue` command with `php artisan horizon` and the healthcheck with `healthcheck-horizon`.

## Slow network

- Build the images once and push them, then replace `build:` with the pushed image on other machines:
  `docker build --target prod -t you/larado:prod . && docker push you/larado:prod`
- `pecl.php.net` (xdebug) times out sometimes; running the build again usually works. The xdebug `RUN` is its own layer, so a retry doesn't redo the rest.
- Node's `fetch` ignores `HTTPS_PROXY` unless `NODE_USE_ENV_PROXY=1` is set (needed for the `bunny` fonts plugin on `npm run build`):
  `NODE_USE_ENV_PROXY=1 HTTPS_PROXY=http://127.0.0.1:10808 npm run build`
- If a build fails, Compose silently reuses the old image. Check which user the image has: `docker run --rm --entrypoint id larado:dev`.

## Ports already taken

Several projects on one machine collide on `3306`, `6379` and `8080`. Change `FORWARD_DB_PORT`, `FORWARD_REDIS_PORT` and `PMA_PORT` per project. The container names use `APP_NAME`, so they differ already.

## PHP version

Default is `8.4`. Pick another when installing:

```sh
curl -fsSL https://raw.githubusercontent.com/mnr73/larado/main/install.sh | PHP_VERSION=8.3 sh
```

Or change `PHP_VERSION` in `.env` later and run `docker compose up -d --build`. The value is the tag prefix of `serversideup/php:<version>-fpm-nginx`.
