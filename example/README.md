# WordPress Dev Environment

This example gives you a local WordPress stack for development. It runs the dev image from this repository with MySQL.

## Prerequisites

- Docker
- Docker Compose

## Quick start

```bash
cd example
docker compose up -d
# Open http://localhost:8080
```

What you get:

- WordPress files mounted from `example/src` to `/home/site/wwwroot`
- MySQL data stored in the `db_data` volume
- Sync enabled, with no plugin mounts in the simple setup

## Contributor workflow

Use `docker-compose.dev.yml` when you are working on the image or the bundled plugin. It adds mounts and Xdebug support, and it builds a local dev image if one is missing.

```bash
cd example
docker compose -f docker-compose.dev.yml up -d --build
# Open http://localhost:8080
```

## Build your own dev image

To build the PHP 8.4 dev image yourself:

```bash
# From the repo root
docker build --target dev --build-arg PHP_VERSION=8.4 -t local/wordpress-azure:8.4-dev .
```

Then point `example/docker-compose.yml` or `example/docker-compose.dev.yml` to `local/wordpress-azure:8.4-dev` and start the stack:

```bash
cd example
docker compose up -d --build
```

## Plugin feedback loop

With `docker-compose.dev.yml`, the `wordpress-azure-monitor` plugin is live-mounted into the container.

- Host path: `../wordpress-plugin/wordpress-azure-monitor`
- Container path: `/home/site/wwwroot/wp-content/plugins/wordpress-azure-monitor`
- Live path: `/homelive/site/wwwroot/wp-content/plugins/wordpress-azure-monitor`

Activate the plugin once:

```bash
cd example
docker compose -f docker-compose.dev.yml exec --user www-data -w /home/site/wwwroot wordpress wp plugin activate wordpress-azure-monitor
```

After that, edit on the host and refresh wp-admin.

## Xdebug

The dev Compose file enables `develop,debug` and starts Xdebug on each request. If your IDE listens on port `9003`, make sure the host is `host.docker.internal`, which is set through `XDEBUG_CONFIG`.

## Environment reference

- WordPress document root: `/home/site/wwwroot`
- Logs: `/home/LogFiles/sync`
- Database host: `db`
- Database port: `3306`
- Database name: `wordpress`
- Database user: `wordpress`
- Database password: `wordpress`

## WP-CLI usage

Run WP-CLI inside the `wordpress` service with the correct user and working directory:

```bash
# Show the WordPress core version
docker compose exec --user www-data -w /home/site/wwwroot wordpress wp core version

# List plugins
docker compose exec --user www-data -w /home/site/wwwroot wordpress wp plugin list

# Activate the bundled plugin
docker compose exec --user www-data -w /home/site/wwwroot wordpress wp plugin activate wordpress-azure-monitor

# Run a WP-CLI command non-interactively
docker compose exec -T --user www-data -w /home/site/wwwroot wordpress wp option get siteurl
```

If you use these commands often, add a shell alias:

```bash
alias dcwp='docker compose exec --user www-data -w /home/site/wwwroot wordpress wp'

# Example
dcwp plugin list
```

## Open a shell in the container

```bash
# Root shell
docker compose exec wordpress bash

# www-data shell
docker compose exec --user www-data -w /home/site/wwwroot wordpress bash
```

## Tear down

```bash
cd example
docker compose down -v
```
