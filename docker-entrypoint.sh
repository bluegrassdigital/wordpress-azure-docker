#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p /home/LogFiles/sync/apache2
mkdir -p /home/LogFiles/sync/archive

# Log sync mode early for clarity
if [[ -n "${DOCKER_SYNC_ENABLED:-}" ]]; then
  echo "$(date) [entrypoint] DOCKER_SYNC_ENABLED=1; serving from /homelive"
else
  echo "$(date) [entrypoint] DOCKER_SYNC_ENABLED=0; serving from /home"
fi

# Allow env-driven PHP display_errors toggle (PHP_DISPLAY_ERRORS=On|Off)
if [[ -n "${PHP_DISPLAY_ERRORS:-}" ]]; then
  echo "display_errors=${PHP_DISPLAY_ERRORS}" > /usr/local/etc/php/conf.d/zz-runtime-display-errors.ini
fi

cd /homelive/site/wwwroot

# Tune FPM concurrency and render Apache/PHP configs
if command -v tune-concurrency.sh >/dev/null 2>&1; then
  tune-concurrency.sh || echo "$(date) [entrypoint] tune-concurrency failed (continuing)"
fi

# Point Apache/PHP routing at the active docroot via a stable symlink
mkdir -p /var/www || true
if [[ -n "${DOCKER_SYNC_ENABLED:-}" ]]; then
  ln -sfn /homelive/site/wwwroot /var/www/current
else
  ln -sfn /home/site/wwwroot /var/www/current
fi

# Ensure a simple health endpoint that exercises PHP-FPM
for base in /home/site/wwwroot /homelive/site/wwwroot; do
  mkdir -p "$base" || true
  if [[ ! -f "$base/healthz.php" ]]; then
    echo "<?php echo 'ok';" > "$base/healthz.php" || true
    chown www-data:www-data "$base/healthz.php" || true
  fi
done

# export env to /etc/profile for subshells
eval $(printenv | sed -n "s/^\([^=]\+\)=\(.*\)$/export \1=\2/p" | sed 's/"/\\\"/g' | sed '/=/s//="/' | sed 's/$/"/' >> /etc/profile)

exec "$@"
