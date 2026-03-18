# Developer Guide

This guide is for local work on the image and the bundled plugin.

## Quick start

Use the example stack if you want the fastest path to a working site.

```bash
cd example
docker compose up -d
# open http://localhost:8080
```

## First-time WordPress install

On a fresh local stack, finish setup with WP-CLI:

```bash
docker compose exec --user www-data -w /homelive/site/wwwroot wordpress \
  wp core install \
  --url=http://localhost:8080 \
  --title='Local Dev' \
  --admin_user=admin \
  --admin_password=admin \
  --admin_email=admin@example.com \
  --skip-email
```

## WP-CLI

Run WP-CLI from the WordPress service:

```bash
docker compose exec --user www-data -w /home/site/wwwroot wordpress wp plugin list
```

## Xdebug

The dev image uses port `9003` and `host.docker.internal` by default. Change the host through `XDEBUG_CONFIG` if your setup needs something else.

## Paths you will edit

- Host path: `example/src`
- Persistent path in the container: `/home/site/wwwroot`
- Live path in the container: `/homelive/site/wwwroot`
- Plugin source on the host: `wordpress-plugin/wordpress-azure-monitor`

The plugin is mounted into both WordPress paths for live edits.

## Troubleshooting

- **403 after first boot**: Make sure WordPress exists in `/homelive/site/wwwroot`, then restart the container to rerun sync.
- **Database connection errors**: Check `WORDPRESS_CONFIG_EXTRA` overrides and confirm the `db` service is healthy.
- **No admin bar badge**: Confirm that the plugin is active and inspect `/home/LogFiles/sync`.
