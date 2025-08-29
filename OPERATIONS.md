### Operations Guide

Operational reference for running `bluegrassdigital/wordpress-azure-sync` on Azure App Service or similar.

#### Image variants
- Moving tags (mutable): `:8.3-latest`, `:8.4-latest`, `:8.3-dev-latest`, `:8.4-dev-latest`, `:8.3-dev-stable`, `:8.4-dev-stable`, `:8.x-stable`, and `:<full-php-version>` if reused across releases.
- Immutable (per-build) tags: `:8.3-build-<git-sha>`.
- Note: `:<full-php-version>` reflects the PHP engine version inside the image (e.g., `8.3.11`) but may be retagged by newer builds that keep the same PHP version. Treat it as mutable unless you verify the digest.

#### Key environment variables
- `DOCKER_SYNC_ENABLED=1` to enable `/home` ↔ `/homelive` sync.
- `WEBSITES_ENABLE_APP_SERVICE_STORAGE=true` to persist `/home` on App Service (required for WordPress content persistence and sync).
- `APACHE_DOCUMENT_ROOT=/home/site/wwwroot` (default; served via stable symlink `/var/www/current` inside the container)
- `APACHE_SITE_ROOT=/home/site/` (default)
- `APACHE_LOG_DIR=/home/LogFiles/sync/apache2` (default)
- `WP_CONTENT_ROOT=/home/site/wwwroot/wp-content` (default)
- `WORDPRESS_CONFIG_EXTRA` for local overrides (e.g., disable SSL for local DB).
- `USE_SYSTEM_CRON=1` to run WP cron via system cron (default); set to `0` to use WP's built-in cron.
- `HTACCESS_SANITIZE=1` (optional): audit and comment out legacy `.htaccess` directives incompatible with PHP‑FPM (e.g., `php_value`, cPanel `AddHandler`). Findings are logged to `/home/LogFiles/sync/htaccess-audit.log`. When sanitization is enabled, `php_value/php_flag` settings are migrated into a local `.user.ini` file so intent is preserved under PHP‑FPM.
- New Relic: `NEWRELIC_KEY`, `WEBSITE_HOSTNAME` (agent install is best-effort).

See also sizing and tuning knobs for FPM/Apache/OPcache in `docs/SIZING_TUNING.md` (e.g., `PHP_FPM_MAX_CHILDREN`, `APACHE_KEEPALIVE_TIMEOUT`, `PHP_OPCACHE_MB`).

#### Runtime & health
- Runtime: Apache mpm_event + PHP-FPM (unix socket `/run/php/php-fpm.sock`). No mod_php.
- Healthcheck: HTTP GET `/healthz` every 30s (exercises PHP-FPM). Use this for App Service Health check.
- Local diagnostics: `/ping` and `/status` are available inside the container only.
- Logs: `/home/LogFiles/sync`, Apache at `/home/LogFiles/sync/apache2`.
- Supervisord manages: apache2, php-fpm, cron, ssh, syncinit, sync (Unison).

#### First-time WordPress install (Azure App Service)
- Database: provision MySQL and add an App Setting named `MYSQLCONNSTR_defaultConnection` with the Azure-style connection string:
  - `Data Source=<host>;Database=<db>;User Id=<user>;Password=<pass>`
- Image tag: use an immutable per-build tag (see below). Enable a staging slot with Health check for zero-downtime.
- App settings (recommended):
  - `DOCKER_SYNC_ENABLED=1` (sync /home ↔ /homelive for performance)
  - Optional: `HOST_DOMAIN=<your-domain>` (ensures correct `WP_HOME`/`WP_SITEURL`), `WORDPRESS_CONFIG_EXTRA` for small overrides
- First boot behavior (automatic):
  - Downloads WordPress core to `/home/site/wwwroot` if missing
  - Creates `/home/site/wwwroot/wp-config.php` from the bundled template, reading `MYSQLCONNSTR_defaultConnection`
  - Sets up cron and log rotation
  - When `DOCKER_SYNC_ENABLED=1`, Apache initially serves from `/home` and switches to `/homelive` only after the initial sync completes (atomic docroot switch)
- Complete setup: browse to your site domain and follow the WordPress installer.
- .htaccess: WordPress normally writes this. Apache is configured to allow overrides for the active docroot (`/var/www/current`). If needed, copy our template to `/home/site/wwwroot/.htaccess` (persisted storage) from `file-templates/htaccess-template`.
  - If you see 500 errors after enabling rewrites, audit `/home/LogFiles/sync/htaccess-audit.log` or enable `HTACCESS_SANITIZE=1` to automatically comment out incompatible directives.

#### WordPress Azure Monitor plugin
- Bundled at `/opt/wordpress-azure-monitor` and mirrored to `/home/site/wwwroot/wp-content/plugins/wordpress-azure-monitor` on container start.
- Auto-activation: set `WAZM_AUTO_ACTIVATE=1` in App Settings. Once WordPress core is installed, the container attempts to activate the plugin via WP‑CLI.
- Manual activation (alternative):
```
wp plugin activate wordpress-azure-monitor
```
- To reinstall or activate after removal, run: `wp-azure-tools plugin-reinstall -a`

#### wp-azure-tools CLI
- Maintenance helper available inside the container; run `wp-azure-tools` for usage.
- Common commands: `status`, `plugin-reinstall [-a]`, `rotate-logs`, `fix-perms`, `ensure-uploads`, `run-cron`, `seed-logs`, `seed-content`, `bootstrap-core`, `bootstrap-config`.
- See [docs/wp-azure-tools.md](docs/wp-azure-tools.md) for details.

#### Azure App Service deployment guidance
- Use immutable per-build tags in production (e.g., `bluegrassdigital/wordpress-azure-sync:8.3-build-<git-sha>`), or pin by digest. Avoid `:latest`, `:stable`, and `:<full-php-version>` if you require strict immutability.
- For zero-downtime, deploy to a staging slot with Health check enabled at `/healthz` and swap once healthy. A single-instance app updated in-place may have a brief interruption.
- To apply updates, change the configured image tag or restart the app/slot so App Service pulls the new image. If you wire up webhooks/CD to your registry, a new push to the same tag can trigger an automatic pull + restart.
- Security/patches: we publish patched images (new immutable tags) when upstream components update. Track releases and move to the newer immutable tag via your staging → prod flow.

Deploying files to `/home` (zip deploy/FTP)
- When `DOCKER_SYNC_ENABLED=1`, Apache serves from `/homelive`, and a background sync pushes changes from `/homelive` → `/home`.
- Files deployed directly to `/home/site/wwwroot` (zip deploy/FTP) will not be visible while sync is enabled.
  - Restart the app/slot to pick up the changes. Avoid manual rsync while Unison is running.

Practical flow
- Configure staging slot with an immutable per-build tag (e.g., `:8.3-build-<git-sha>`), or pin by digest.
- Validate, then swap slots.

#### Available tags (what to pick)
- Use for production: `:8.3-build-<git-sha>` (immutable per commit) or a digest pin.
- Acceptable for non-production: `:<full-php-version>` (may move if multiple releases share the same PHP version).
- Avoid in production: `:8.3-latest`, `:8.4-latest`, `:8.x-stable` (moving tags).

#### Upgrades
- To add a PHP version, build with `--build-arg PHP_VERSION=...` and add targets in `docker-bake.hcl` and CI matrix.
- Imagick pinned to 3.8.0 for PHP 8.4+ compatibility.


#### Release process
- See `RELEASING.md` for tag semantics, weekly vs feature releases, and changelog workflow.
