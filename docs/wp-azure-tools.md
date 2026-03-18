# wp-azure-tools CLI

`wp-azure-tools` is the container's maintenance helper. It gathers the routine operational tasks in one place.

## Usage

```bash
wp-azure-tools <command> [options]
```

## Commands

- `status`: Show the environment and the important filesystem paths.
- `plugin-reinstall [-a]`: Reinstall the bundled Azure Monitor plugin. Add `-a` to activate it.
- `rotate-logs`: Force Apache log rotation.
- `fix-perms [path]`: Fix permissions. If you omit `path`, the tool uses the live document root.
- `ensure-uploads`: Make sure the live uploads symlink points to persisted uploads.
- `run-cron [home|homelive]`: Run WordPress cron jobs that are due now.
- `seed-logs`: Rotate logs, then seed them from `/home` into `/homelive`.
- `seed-content`: Seed code and `wp-content`, excluding uploads, between the two trees.
- `bootstrap-core [-f]`: Download or refresh WordPress core. Add `-f` to force the refresh.
- `bootstrap-config [-f]`: Create or refresh `wp-config.php`. Add `-f` to overwrite it.

## Examples

```bash
wp-azure-tools status
wp-azure-tools plugin-reinstall -a
wp-azure-tools run-cron homelive
```
