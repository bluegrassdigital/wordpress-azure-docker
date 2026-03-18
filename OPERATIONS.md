# Operations Guide

This guide is for operators running `bluegrassdigital/wordpress-azure-sync` on Azure App Service or a similar platform.

## What matters most

This image keeps WordPress fast by serving from `/homelive` and syncing that live tree with the persistent `/home` volume. On Azure App Service, that tradeoff matters because persistent storage is durable but slow.

## Image variants

- **Moving tags**: `:8.3-latest`, `:8.4-latest`, `:8.3-dev-latest`, `:8.4-dev-latest`, `:8.3-dev-stable`, `:8.4-dev-stable`, `:8.x-stable`, and sometimes `:<full-php-version>` when reused across releases.
- **Immutable tags**: `:8.3-build-<git-sha>`.
- **Important note**: `:<full-php-version>` reflects the PHP engine version in the image, such as `8.3.11`, but it can still move if a later build keeps that same PHP version. Treat it as mutable unless you pin by digest.

## Key environment variables

- `DOCKER_SYNC_ENABLED=1`: Enable `/home` ↔ `/homelive` sync.
- `WEBSITES_ENABLE_APP_SERVICE_STORAGE=true`: Persist `/home` on App Service. This is required for WordPress content to survive restarts.
- `APACHE_DOCUMENT_ROOT=/home/site/wwwroot`: Default document root.
- `APACHE_SITE_ROOT=/home/site/`: Default site root.
- `APACHE_LOG_DIR=/home/LogFiles/sync/apache2`: Default Apache log path.
- `WP_CONTENT_ROOT=/home/site/wwwroot/wp-content`: Default content root.
- `WORDPRESS_CONFIG_EXTRA`: Add small local overrides.
- `USE_SYSTEM_CRON=1`: Run WordPress cron through the system scheduler. Set it to `0` to use WordPress's built-in cron.
- `NEWRELIC_KEY` and `WEBSITE_HOSTNAME`: Enable New Relic when needed. Installation is best-effort.

## Logs and health

- Health check: HTTP on `/` every 30 seconds.
- Sync logs: `/home/LogFiles/sync`
- Apache logs: `/home/LogFiles/sync/apache2`
- Managed processes: Apache, cron, SSH, `syncinit`, and Unison under `supervisord`

## First-time Azure App Service install

### 1. Set the database connection

Create an App Setting named `MYSQLCONNSTR_defaultConnection` with an Azure-style connection string:

```text
Data Source=<host>;Database=<db>;User Id=<user>;Password=<pass>
```

### 2. Choose the image tag

Use an immutable per-build tag in production. A staging slot with Health Check enabled is the safest place to test it.

### 3. Add the core settings

- `DOCKER_SYNC_ENABLED=1`
- `WEBSITES_ENABLE_APP_SERVICE_STORAGE=true`
- Optional: `HOST_DOMAIN=<your-domain>`
- Optional: `WORDPRESS_CONFIG_EXTRA=<php code>`
- Optional: `WAZM_AUTO_ACTIVATE=1`

### 4. Know what first boot does

On first boot, the container:

- downloads WordPress core to `/home/site/wwwroot` if it is missing
- creates `/home/site/wwwroot/wp-config.php` from the bundled template
- reads `MYSQLCONNSTR_defaultConnection`
- sets up cron and log rotation
- switches Apache to `/homelive` when sync is enabled

### 5. Finish setup

Open the site in a browser and complete the WordPress installer.

WordPress usually writes `.htaccess` on its own. If you need a starting file, copy `file-templates/htaccess-template` into `/home/site/wwwroot/.htaccess`.

## WordPress Azure Monitor plugin

The image bundles the plugin at `/opt/wordpress-azure-monitor` and mirrors it into `/home/site/wwwroot/wp-content/plugins/wordpress-azure-monitor` on container start.

To activate it:

- set `WAZM_AUTO_ACTIVATE=1` in App Settings, or
- run `wp plugin activate wordpress-azure-monitor`, or
- run `wp-azure-tools plugin-reinstall -a`

## wp-azure-tools CLI

`wp-azure-tools` is the maintenance helper inside the container. Use it for routine tasks such as `status`, `plugin-reinstall`, `rotate-logs`, `fix-perms`, `ensure-uploads`, `run-cron`, `seed-logs`, `seed-content`, `bootstrap-core`, and `bootstrap-config`.

For command details, see [docs/wp-azure-tools.md](docs/wp-azure-tools.md).

## Deployment guidance

- Use immutable per-build tags in production, such as `bluegrassdigital/wordpress-azure-sync:8.3-build-<git-sha>`, or pin by digest.
- Avoid `:latest`, `:stable`, and `:<full-php-version>` if you need strict immutability.
- Deploy to a staging slot with Health Check enabled, then swap after the slot is healthy.
- To roll out a new image, change the configured tag or restart the app so App Service pulls the image.
- Follow releases and move forward to newer immutable tags as upstream patches arrive.

## Deploying files to `/home`

When `DOCKER_SYNC_ENABLED=1`, Apache serves from `/homelive`. Files pushed directly to `/home/site/wwwroot` through Zip Deploy or FTP will not appear until the app restarts.

If you deploy files to `/home`, restart the app or slot. Do not run manual `rsync` while Unison is active.

## Which tag to use

- **Production**: `:8.3-build-<git-sha>` or a pinned digest
- **Non-production**: `:<full-php-version>` if a moving tag is acceptable
- **Avoid in production**: `:8.3-latest`, `:8.4-latest`, `:8.x-stable`

## Upgrades

- To add a PHP version, build with `--build-arg PHP_VERSION=...` and update `docker-bake.hcl` plus the CI matrix.
- `imagick` is pinned to `3.8.0` for PHP 8.4+ compatibility.

## Release process

See [RELEASING.md](RELEASING.md) for tag policy, release cadence, and changelog workflow.
