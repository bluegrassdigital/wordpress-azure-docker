# WordPress on Azure App Service

This repository packages WordPress for Azure App Service on Linux.

The idea is straightforward. Serve WordPress from a fast local path, `/homelive`, and keep it in sync with the persistent Azure path, `/home`. That reduces the penalty of slow storage without giving up durability.

## What the image includes

- A production-ready WordPress image built on PHP 8.3 or 8.4 with Apache
- Common PHP extensions, a health check, `supervisord`, and an optional Azure Monitor plugin
- `rsync` and Unison support when `DOCKER_SYNC_ENABLED=1`

## Quick start for Azure App Service

### 1. Use a stable image tag

For production, use an immutable build tag such as `bluegrassdigital/wordpress-azure-sync:8.3-build-<git-sha>`. Avoid floating tags like `:latest` or `:stable`.

### 2. Set the App Settings

- `MYSQLCONNSTR_defaultConnection=Data Source=<host>;Database=<db>;User Id=<user>;Password=<pass>`
- `WEBSITES_ENABLE_APP_SERVICE_STORAGE=true`
- `DOCKER_SYNC_ENABLED=1`
- Optional: `USE_SYSTEM_CRON=1`
- Optional: `HOST_DOMAIN=<your-domain>`
- Optional: `WORDPRESS_CONFIG_EXTRA=<php code>`
- Optional: `WAZM_AUTO_ACTIVATE=1`

### 3. Know what first boot does

If `/home/site/wwwroot` is empty, the container downloads WordPress and creates `wp-config.php` from the bundled template. Then finish setup by visiting the site URL.

### 4. Handle `.htaccess` only if you need to

WordPress usually writes `.htaccess` on its own. If you want a hardened starting point, use `file-templates/htaccess-template`.

### 5. Prefer deployment slots

For safer releases, use deployment slots with Health Check enabled. Warm the slot first. Swap only when it is ready.

## Deploying file changes

When `DOCKER_SYNC_ENABLED=1`, the running site is served from `/homelive`. Files pushed to `/home/site/wwwroot` through Zip Deploy or FTP will not appear until the app restarts.

If you deploy files to `/home`, restart the app or slot. Do not run manual `rsync` while Unison is active.

## Where to read next

- Documentation index: [`docs/`](docs/README.md)
- Operations guide: [`OPERATIONS.md`](OPERATIONS.md)
- Maintenance commands: [`docs/wp-azure-tools.md`](docs/wp-azure-tools.md)
- Developer workflow: [`DEV.md`](DEV.md)
- WordPress admin guide for the optional plugin: [`docs/wordpress-azure-monitor.md`](docs/wordpress-azure-monitor.md)
- Release process: [`RELEASING.md`](RELEASING.md)

If you are contributing locally, build the dev variant first:

```bash
docker build --target dev --build-arg PHP_VERSION=8.4 -t local/wordpress-azure:8.4-dev .
```

Then point your Compose file to `local/wordpress-azure:8.4-dev`.

## License

MIT
