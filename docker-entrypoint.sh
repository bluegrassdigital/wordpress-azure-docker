#!/usr/bin/env bash
set -Eeuo pipefail

# Validate before starting Apache or any other process. An unset or empty value
# keeps PHP's upload progress disabled; only an explicit 1 enables it.
case "${PHP_SESSION_UPLOAD_PROGRESS_ENABLED:-0}" in
  0) ;;
  1) echo "Warning: PHP session upload progress is enabled; the session upload progress mitigation is disabled." >&2 ;;
  *) echo "PHP_SESSION_UPLOAD_PROGRESS_ENABLED must be 0 (disabled) or 1 (enabled)." >&2; exit 64 ;;
esac

mkdir -p /home/LogFiles/sync/apache2
mkdir -p /home/LogFiles/sync/archive

# Allow env-driven PHP display_errors toggle (PHP_DISPLAY_ERRORS=On|Off)
if [[ -n "${PHP_DISPLAY_ERRORS:-}" ]]; then
  echo "display_errors=${PHP_DISPLAY_ERRORS}" > /usr/local/etc/php/conf.d/zz-runtime-display-errors.ini
fi

cd /homelive/site/wwwroot

# Keep cron and root login shell settings in one startup snapshot.
install -d -m 0755 /etc/profile.d
/usr/local/bin/write-container-env.sh /etc/profile.d/wordpress-container-env.sh

exec "$@"
