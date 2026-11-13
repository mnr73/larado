# Larado

Docker setup for Laravel on top of [serversideup/php](https://serversideup.net/open-source/docker-php/) (`fpm-nginx`). Three files are copied into the project. `docker compose up -d --build` starts everything.

## What it runs

| Service | Role |
|---|---|
| `app` | nginx + PHP-FPM. Runs migrations and the Laravel caches at start (`AUTORUN_ENABLED`). |
| `queue` | `queue:work`, `QUEUE_REPLICAS` copies (default 2), with a healthcheck. |
| `scheduler` | `schedule:work`, with a healthcheck. |
| `mysql` | MySQL 8.4. |
| `redis` | Redis 7. |
| `phpmyadmin` | Dev only. |

Extensions: the image ships with `pcntl`, `redis`, `zip`, `pdo_mysql` and `opcache`. `Dockerfile` adds `gd intl exif sockets mysqli`. The `dev` stage also adds `xdebug`.

## Install

In the root of a Laravel project:

```sh
curl -fsSL https://raw.githubusercontent.com/mnr73/larado/main/install.sh | sh
```

This downloads `Dockerfile`, `compose.yml` and `compose.dev.yml`, and appends the larado variables from `.env.larado.example` to `.env`. It never touches an existing `LARADO_IMAGE`.

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
| `XDEBUG_MODE` | `develop,debug` | Dev only. |
| `PUID` / `PGID` | `1000` | Dev only. Build-time user id of `www-data`. |

Any other `PHP_*` or `NGINX_*` setting works as an env var; see the [variable reference](https://serversideup.net/open-source/docker-php/docs/reference/environment-variable-specification).

## Xdebug

Port `9003`, `start_with_request=yes`, host `host.docker.internal`. Point your IDE at that port. Turn it off with `XDEBUG_MODE=off` and `docker compose up -d`.

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
