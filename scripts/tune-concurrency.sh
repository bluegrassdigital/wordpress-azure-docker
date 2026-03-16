#!/usr/bin/env bash
set -euo pipefail

# This script tunes PHP-FPM concurrency and renders Apache/FPM configs
# based on environment variables. It aims to be dependency-free.

log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [tune] $*"; }

# -------- Memory detection --------
to_mb() {
  awk '{printf("%.0f", $1 / (1024*1024))}'
}

detect_mem_limit_mb() {
  # cgroup v2
  if [[ -f /sys/fs/cgroup/memory.max ]]; then
    local v
    v=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo 0)
    if [[ "$v" != "max" && "$v" =~ ^[0-9]+$ && "$v" -gt 0 ]]; then
      echo "$v" | to_mb
      return
    fi
  fi
  # cgroup v1
  if [[ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
    local v
    v=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo 0)
    if [[ "$v" =~ ^[0-9]+$ && "$v" -gt 0 && "$v" -lt 9223372036854771712 ]]; then
      echo "$v" | to_mb
      return
    fi
  fi
  # Fallback to MemTotal
  local mem_kb
  mem_kb=$(awk '/MemTotal:/ {printf "%.0f\n", $2*1024}' /proc/meminfo 2>/dev/null || echo 0)
  if [[ "$mem_kb" -gt 0 ]]; then
    echo "$mem_kb" | to_mb
    return
  fi
  # Last resort
  echo 2048
}

clamp() {
  local val=$1 min=$2 max=$3
  if (( val < min )); then echo "$min"; return; fi
  if (( val > max )); then echo "$max"; return; fi
  echo "$val"
}

# -------- Compute FPM children --------
MEM_LIMIT_MB=$(detect_mem_limit_mb)
PHP_CHILD_MB=${PHP_CHILD_MB:-48}
HEADROOM_PCT=15
HEADROOM_ABS_MB=1024
calc_headroom=$(( (MEM_LIMIT_MB * HEADROOM_PCT) / 100 ))
HEADROOM_MB=$(( calc_headroom > HEADROOM_ABS_MB ? calc_headroom : HEADROOM_ABS_MB ))

if [[ -z "${PHP_FPM_MAX_CHILDREN:-}" ]]; then
  usable=$(( MEM_LIMIT_MB - HEADROOM_MB ))
  if (( usable < PHP_CHILD_MB )); then usable=$PHP_CHILD_MB; fi
  est=$(( usable / PHP_CHILD_MB ))
  PHP_FPM_MAX_CHILDREN=$(clamp "$est" 50 800)
  export PHP_FPM_MAX_CHILDREN
  log "Auto-tuned pm.max_children=${PHP_FPM_MAX_CHILDREN} (limit=${MEM_LIMIT_MB}MB, headroom=${HEADROOM_MB}MB, child=${PHP_CHILD_MB}MB)"
else
  log "Using provided pm.max_children=${PHP_FPM_MAX_CHILDREN} (limit=${MEM_LIMIT_MB}MB)"
fi

PHP_FPM_PM=${PHP_FPM_PM:-dynamic}
PHP_FPM_START_SERVERS=${PHP_FPM_START_SERVERS:-10}
PHP_FPM_MIN_SPARE_SERVERS=${PHP_FPM_MIN_SPARE_SERVERS:-10}
PHP_FPM_MAX_SPARE_SERVERS=${PHP_FPM_MAX_SPARE_SERVERS:-20}
PHP_FPM_MAX_REQUESTS=${PHP_FPM_MAX_REQUESTS:-1000}
PHP_FPM_REQ_TMO=${PHP_FPM_REQ_TMO:-120}
PHP_FPM_SLOWLOG=${PHP_FPM_SLOWLOG:-0}

APACHE_KEEPALIVE_TIMEOUT=${APACHE_KEEPALIVE_TIMEOUT:-2}
APACHE_MAX_KEEPALIVE_REQUESTS=${APACHE_MAX_KEEPALIVE_REQUESTS:-100}
APACHE_PROXY_TIMEOUT=${APACHE_PROXY_TIMEOUT:-120}

PHP_OPCACHE_MB=${PHP_OPCACHE_MB:-192}
PHP_OPCACHE_MAX_FILES=${PHP_OPCACHE_MAX_FILES:-100000}
PHP_OPCACHE_REVALIDATE_SEC=${PHP_OPCACHE_REVALIDATE_SEC:-2}

mkdir -p /run/php || true

# -------- Render PHP-FPM pool config --------
render_fpm_pool() {
  # Support both official PHP layout (/usr/local/etc/php-fpm.d) and Debian layout (/etc/php/*/fpm)
  local deb_dir="/etc/php" fpm_dir
  if [[ -d /usr/local/etc/php-fpm.d ]]; then
    fpm_dir="/usr/local/etc/php-fpm.d"
    cat >"${fpm_dir}/www.conf" <<CONF
[www]
user = www-data
group = www-data
listen = /run/php/php-fpm.sock
listen.owner = www-data
listen.group = www-data
clear_env = no
pm = ${PHP_FPM_PM}
pm.max_children = ${PHP_FPM_MAX_CHILDREN}
pm.start_servers = ${PHP_FPM_START_SERVERS}
pm.min_spare_servers = ${PHP_FPM_MIN_SPARE_SERVERS}
pm.max_spare_servers = ${PHP_FPM_MAX_SPARE_SERVERS}
pm.max_requests = ${PHP_FPM_MAX_REQUESTS}
request_terminate_timeout = ${PHP_FPM_REQ_TMO}s
slowlog = /home/LogFiles/php-fpm.slow.log
request_slowlog_timeout = ${PHP_FPM_SLOWLOG}s
ping.path = /ping
pm.status_path = /status
catch_workers_output = yes
access.log = /home/LogFiles/php-fpm.access.log
php_admin_value[error_log] = ${APACHE_LOG_DIR:-/home/LogFiles/sync/apache2}/php-fpm-error.log
php_admin_flag[log_errors] = on
CONF
  elif [[ -d "$deb_dir" ]]; then
    # Find first fpm version dir
    local ver
    ver=$(ls "$deb_dir" | grep -E '^[0-9]+\.[0-9]+' | sort -V | tail -n1 || true)
    if [[ -n "$ver" ]]; then
      fpm_dir="$deb_dir/$ver/fpm"
      mkdir -p "$fpm_dir/pool.d"
      cat >"$fpm_dir/pool.d/www.conf" <<CONF
[www]
user = www-data
group = www-data
listen = /run/php/php-fpm.sock
listen.owner = www-data
listen.group = www-data
clear_env = no
pm = ${PHP_FPM_PM}
pm.max_children = ${PHP_FPM_MAX_CHILDREN}
pm.start_servers = ${PHP_FPM_START_SERVERS}
pm.min_spare_servers = ${PHP_FPM_MIN_SPARE_SERVERS}
pm.max_spare_servers = ${PHP_FPM_MAX_SPARE_SERVERS}
pm.max_requests = ${PHP_FPM_MAX_REQUESTS}
request_terminate_timeout = ${PHP_FPM_REQ_TMO}s
slowlog = /home/LogFiles/php-fpm.slow.log
request_slowlog_timeout = ${PHP_FPM_SLOWLOG}s
ping.path = /ping
pm.status_path = /status
catch_workers_output = yes
access.log = /home/LogFiles/php-fpm.access.log
php_admin_value[error_log] = ${APACHE_LOG_DIR:-/home/LogFiles/sync/apache2}/php-fpm-error.log
php_admin_flag[log_errors] = on
CONF
    fi
  fi

  # Ensure official image override doesn't force TCP 9000
  if [[ -f /usr/local/etc/php-fpm.d/zz-docker.conf ]]; then
    sed -ri 's#^\s*listen\s*=.*#listen = /run/php/php-fpm.sock#' /usr/local/etc/php-fpm.d/zz-docker.conf || true
  fi
}

# -------- Render Apache confs --------
render_apache_confs() {
  # php-fpm handler + fcgi proxy
  cat >/etc/apache2/conf-available/php-fpm.conf <<CONF
# Route PHP requests to php-fpm via unix socket using ProxyPassMatch
ProxyPassMatch ^/(.*\\.php(/.*)?)$ unix:/run/php/php-fpm.sock|fcgi://localhost/var/www/current/\$1
ProxyFCGIBackendType GENERIC

# Expose php-fpm ping and status locally
<LocationMatch "^/(ping|status)$">
    SetHandler "proxy:unix:/run/php/php-fpm.sock|fcgi://localhost/"
    Require local
</LocationMatch>

# Map /healthz to a tiny PHP script (created at startup)
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteRule ^/healthz$ /healthz.php [PT]
</IfModule>

ProxyTimeout ${APACHE_PROXY_TIMEOUT}
CONF

  # KeepAlive tuning
  cat >/etc/apache2/conf-available/keepalive.conf <<CONF
KeepAlive On
MaxKeepAliveRequests ${APACHE_MAX_KEEPALIVE_REQUESTS}
KeepAliveTimeout ${APACHE_KEEPALIVE_TIMEOUT}
CONF

  # Server-status local only
  cat >/etc/apache2/conf-available/status-local.conf <<CONF
<Location /server-status>
    SetHandler server-status
    Require local
</Location>
CONF

  a2enconf php-fpm keepalive status-local >/dev/null 2>&1 || true
}

# -------- Render PHP opcache defaults --------
render_php_opcache() {
  cat >/usr/local/etc/php/conf.d/zz-opcache-runtime.ini <<CONF
opcache.enable=1
opcache.memory_consumption=${PHP_OPCACHE_MB}
opcache.max_accelerated_files=${PHP_OPCACHE_MAX_FILES}
opcache.revalidate_freq=${PHP_OPCACHE_REVALIDATE_SEC}
CONF
}

render_fpm_pool
render_apache_confs
render_php_opcache

log "Render complete. pm=${PHP_FPM_PM} max_children=${PHP_FPM_MAX_CHILDREN} max_requests=${PHP_FPM_MAX_REQUESTS} keepalive=${APACHE_KEEPALIVE_TIMEOUT}s proxy_timeout=${APACHE_PROXY_TIMEOUT}s"
