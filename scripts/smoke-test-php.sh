#!/usr/bin/env bash
set -Eeuo pipefail

# Verify the PHP ABI and Apache runtime for a built image.
# Usage: scripts/smoke-test-php.sh <image> <exact-version> [base|runtime|dev]
# Example: scripts/smoke-test-php.sh wordpress-azure-emergency:8.3.36-emergency-source-local 8.3.36 runtime

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <image> <exact-version> [base|runtime|dev]" >&2
  exit 2
fi

IMAGE="$1"
EXPECTED_VERSION="$2"
VARIANT="${3:-runtime}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
case "$VARIANT" in
  base|runtime|dev) ;;
  *) echo "Variant must be base, runtime, or dev" >&2; exit 2 ;;
esac
if [[ ! "$EXPECTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected version must be an exact version such as 8.3.36" >&2
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 2
fi

WAIT_SECONDS="${PHP_SMOKE_WAIT_SECONDS:-240}"
if [[ ! "$WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "PHP_SMOKE_WAIT_SECONDS must be a positive integer" >&2
  exit 2
fi

CONTAINERS=()
VOLUMES=()
show_failure_logs() {
  local container="$1"
  echo "[php-smoke] Recent container output for $container:" >&2
  docker logs --tail 120 "$container" >&2 2>/dev/null || true
  docker exec "$container" sh -c \
    'for f in /home/LogFiles/sync/sync-init.current.log /homelive/LogFiles/sync/sync-init.current.log /home/LogFiles/sync/supervisor.log /home/LogFiles/supervisord.log; do if [ -f "$f" ]; then echo "--- $f"; tail -n 80 "$f"; fi; done' \
    >&2 2>/dev/null || true
}

cleanup() {
  local status=$?
  trap - EXIT
  if (( status != 0 )); then
    for container in ${CONTAINERS[@]+"${CONTAINERS[@]}"}; do
      show_failure_logs "$container"
    done
  fi
  for container in ${CONTAINERS[@]+"${CONTAINERS[@]}"}; do
    docker rm -f "$container" >/dev/null 2>&1 || true
  done
  for volume in ${VOLUMES[@]+"${VOLUMES[@]}"}; do
    docker volume rm "$volume" >/dev/null 2>&1 || true
  done
  exit "$status"
}
trap cleanup EXIT

assert_cli_version() {
  local container="$1"
  local version config_version header_version image_php_version image_sha expected_sha actual_sha source_dockerfile actual

  version="$(docker exec "$container" php -r 'echo PHP_VERSION;')"
  config_version="$(docker exec "$container" php-config --version)"
  header_version="$(docker exec "$container" sed -n 's/^#define PHP_VERSION "\([^"]*\)"/\1/p' /usr/local/include/php/main/php_version.h)"
  image_php_version="$(docker exec "$container" sh -c 'printf %s "${PHP_VERSION:-}"')"

  for actual in "$version" "$config_version" "$header_version"; do
    if [[ "$actual" != "$EXPECTED_VERSION" ]]; then
      echo "[php-smoke] PHP version mismatch in $container: expected $EXPECTED_VERSION, got '$actual'" >&2
      return 1
    fi
  done
  if [[ -n "$image_php_version" && "$image_php_version" != "$EXPECTED_VERSION" ]]; then
    echo "[php-smoke] Image PHP_VERSION is '$image_php_version', expected '$EXPECTED_VERSION'" >&2
    return 1
  fi

  # Verify the source tarball retained by the official recipe against its pinned checksum.
  source_dockerfile="$REPO_ROOT/php-source/${EXPECTED_VERSION%.*}/Dockerfile"
  if [[ -f "$source_dockerfile" ]]; then
    expected_sha="$(sed -n 's/^ENV PHP_SHA256="\([0-9a-fA-F]*\)".*/\1/p' "$source_dockerfile" | head -n 1)"
    image_sha="$(docker exec "$container" sh -c 'printf %s "${PHP_SHA256:-}"')"
    actual_sha="$(docker exec "$container" sha256sum /usr/src/php.tar.xz | awk '{print $1}')"
    if [[ -z "$expected_sha" || "$actual_sha" != "$expected_sha" || "$image_sha" != "$expected_sha" ]]; then
      echo "[php-smoke] PHP source checksum mismatch: expected $expected_sha, tarball $actual_sha, image metadata '${image_sha:-unset}'" >&2
      return 1
    fi
  fi
  echo "[php-smoke] PHP $version, php-config $config_version, and PHP header $header_version verified"
}

assert_extensions() {
  local container="$1"
  local extensions="$2"
  docker exec "$container" php -r '
    foreach (explode(",", $argv[1]) as $extension) {
      $phpExtension = $extension === "opcache" ? "Zend OPcache" : $extension;
      if (!extension_loaded($phpExtension)) {
        fwrite(STDERR, "Missing PHP extension: $phpExtension\n");
        exit(1);
      }
    }
  ' -- "$extensions"
}

assert_apache_modules() {
  local container="$1"
  local modules
  docker exec "$container" apache2ctl -t
  modules="$(docker exec "$container" apache2ctl -M 2>&1)"
  for module in php_module mpm_prefork_module; do
    if ! grep -Eq "^[[:space:]]*${module}[[:space:]]" <<<"$modules"; then
      echo "[php-smoke] Required Apache module $module is not enabled" >&2
      return 1
    fi
  done
  if [[ "$VARIANT" != base ]]; then
    for module in rewrite_module expires_module headers_module remoteip_module; do
      if ! grep -Eq "^[[:space:]]*${module}[[:space:]]" <<<"$modules"; then
        echo "[php-smoke] Required Apache module $module is not enabled" >&2
        return 1
      fi
    done
  fi
}

wait_for_init() {
  local container="$1"
  local log_path="$2"
  local marker="$3"
  local deadline=$((SECONDS + WAIT_SECONDS))
  while (( SECONDS < deadline )); do
    if docker exec "$container" sh -c 'test -f "$1" && grep -Fq "$2" "$1"' sh "$log_path" "$marker"; then
      return 0
    fi
    if ! docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null | grep -qx true; then
      echo "[php-smoke] Container exited before startup completed: $container" >&2
      return 1
    fi
    sleep 2
  done
  echo "[php-smoke] Timed out waiting for init marker '$marker' in $log_path" >&2
  return 1
}

assert_wordpress_bootstrap() {
  local container="$1"
  local docroot="$2"
  local version
  docker exec "$container" test -s "$docroot/index.php"
  docker exec "$container" test -s "$docroot/wp-config.php"
  version="$(docker exec "$container" wp --allow-root --path="$docroot" core version)"
  if [[ -z "$version" ]]; then
    echo "[php-smoke] wp-cli did not report a WordPress core version" >&2
    return 1
  fi
  echo "[php-smoke] WordPress core $version and wp-config.php found in $docroot"
}

assert_http_php() {
  local container="$1"
  local docroot="$2"
  local extensions="$3"
  local probe="$docroot/.php-smoke-$$.php"
  local response
  docker exec -i "$container" sh -c 'cat > "$1"' sh "$probe" <<PHP
<?php
header('Content-Type: application/json');
\$extensions = explode(',', '${extensions}');
\$loaded = [];
foreach (\$extensions as \$extension) {
    \$phpExtension = \$extension === 'opcache' ? 'Zend OPcache' : \$extension;
    \$loaded[\$extension] = extension_loaded(\$phpExtension);
}
echo json_encode([
    'version' => PHP_VERSION,
    'sapi' => PHP_SAPI,
    'extensions' => \$loaded,
], JSON_UNESCAPED_SLASHES);
PHP

  local deadline=$((SECONDS + WAIT_SECONDS))
  while (( SECONDS < deadline )); do
    if response="$(docker exec "$container" curl -fsS --max-time 5 http://127.0.0.1/"$(basename "$probe")" 2>/dev/null)"; then
      if [[ "$response" == *"\"version\":\"$EXPECTED_VERSION\""* && "$response" == *'"sapi":"apache2handler"'* ]]; then
        local extension
        IFS=',' read -r -a required_extensions <<< "$extensions"
        for extension in "${required_extensions[@]}"; do
          if [[ "$response" != *"\"$extension\":true"* ]]; then
            echo "[php-smoke] HTTP PHP probe did not load $extension: $response" >&2
            return 1
          fi
        done
        docker exec "$container" rm -f "$probe"
        echo "[php-smoke] HTTP probe reports PHP $EXPECTED_VERSION via apache2handler with required extensions"
        return 0
      fi
    fi
    sleep 2
  done
  echo "[php-smoke] Timed out waiting for a valid HTTP PHP probe at $probe" >&2
  docker exec "$container" rm -f "$probe" >/dev/null 2>&1 || true
  return 1
}

run_base_case() {
  local container="wazm-php-smoke-$$-base"
  CONTAINERS+=("$container")
  echo "[php-smoke] Starting base image with its default entrypoint: $IMAGE"
  docker run -d --name "$container" "$IMAGE" >/dev/null
  assert_cli_version "$container"
  assert_extensions "$container" "opcache,sodium"
  assert_apache_modules "$container"
  assert_http_php "$container" "/var/www/html" "opcache,sodium"
}

run_application_case() {
  local sync_mode="$1"
  local container="wazm-php-smoke-$$-${VARIANT}-${sync_mode}"
  local volume="wazm-php-smoke-$$-${VARIANT}-${sync_mode}-home"
  local docroot log_path marker
  if [[ "$sync_mode" == enabled ]]; then
    docroot="/homelive/site/wwwroot"
    log_path="/homelive/LogFiles/sync/sync-init.current.log"
    marker="Sync enabled - init complete"
  else
    docroot="/home/site/wwwroot"
    log_path="/home/LogFiles/sync/sync-init.current.log"
    marker="Sync disabled - init complete"
  fi

  VOLUMES+=("$volume")
  CONTAINERS+=("$container")
  docker volume create "$volume" >/dev/null
  echo "[php-smoke] Starting $VARIANT image with sync $sync_mode: $IMAGE"
  if [[ "$sync_mode" == enabled ]]; then
    docker run -d --name "$container" \
      --mount "type=volume,src=$volume,dst=/home" \
      -e DOCKER_SYNC_ENABLED=1 \
      -e WAZM_AUTO_ACTIVATE= \
      -e USE_SYSTEM_CRON=0 \
      "$IMAGE" >/dev/null
  else
    docker run -d --name "$container" \
      --mount "type=volume,src=$volume,dst=/home" \
      -e DOCKER_SYNC_ENABLED= \
      -e WAZM_AUTO_ACTIVATE= \
      -e USE_SYSTEM_CRON=0 \
      "$IMAGE" >/dev/null
  fi

  assert_cli_version "$container"
  local required_extensions="apcu,bcmath,exif,gd,mysqli,zip,opcache,soap,pdo,pdo_mysql,imagick"
  if [[ "$VARIANT" == dev ]]; then
    required_extensions+=",xdebug"
  fi
  assert_extensions "$container" "$required_extensions"
  wait_for_init "$container" "$log_path" "$marker"
  assert_apache_modules "$container"
  assert_wordpress_bootstrap "$container" "$docroot"
  assert_http_php "$container" "$docroot" "$required_extensions"
}

if [[ "$VARIANT" == base ]]; then
  run_base_case
else
  run_application_case enabled
  run_application_case disabled
fi

echo "[php-smoke] PASS: $IMAGE ($EXPECTED_VERSION, $VARIANT)"
