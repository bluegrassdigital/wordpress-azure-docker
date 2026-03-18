# WordPress Azure Monitor plugin

This image includes an optional plugin that brings sync status and log access into WordPress admin.

## What it does

- Shows the current `/home` ↔ `/homelive` sync state in the admin bar.
- Adds an **Azure Monitor** menu in wp-admin.
- Lets administrators view, refresh, and download files from `/home/LogFiles/sync`.
- Protects admin actions with capability checks and nonces.

## Installation

1. Make sure persistent storage is enabled.
2. On container start, the plugin is mirrored from `/opt/wordpress-azure-monitor` to `/home/site/wwwroot/wp-content/plugins/wordpress-azure-monitor`.
3. Activate it in one of these ways:
   - Set `WAZM_AUTO_ACTIVATE=1` in App Settings.
   - Run `wp plugin activate wordpress-azure-monitor` with WP-CLI.
   - Run `wp-azure-tools plugin-reinstall -a` to reinstall and activate it in one step.

Once active, the plugin adds the status badge to the admin bar and exposes the log view through **Azure Monitor** in the dashboard.
