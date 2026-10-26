#!/usr/bin/env bash
set -Eeuo pipefail

# Exercise the real image entrypoint and Apache PHP SAPI. No host ports or
# persistent WordPress data are used, and no WordPress bootstrap is needed.
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <image>" >&2
  exit 2
fi
IMAGE="$1"
CONTAINERS=()
cleanup() {
  local status=$?
  for container in ${CONTAINERS[@]+"${CONTAINERS[@]}"}; do
    if (( status != 0 )); then
      docker logs --tail 30 "$container" >&2 2>/dev/null || true
    fi
    docker rm -f "$container" >/dev/null 2>&1 || true
  done
  return "$status"
}
trap cleanup EXIT

# The baked configuration must also be safe for a command that bypasses startup.
docker run --rm --entrypoint php "$IMAGE" -r '
  if ((bool) ini_get("session.upload_progress.enabled")) exit(1);
'

run_case() {
  local label="$1" expected="$2"
  shift 2
  local container="wazm-session-$$-$label" response ready=0
  CONTAINERS+=("$container")
  docker run -d --name "$container" "$@" "$IMAGE" bash -c '
    set -Eeuo pipefail
    mkdir -p "$APACHE_DOCUMENT_ROOT"
    cat > "$APACHE_DOCUMENT_ROOT/session-probe.php" <<'"'"'PHP'"'"'
<?php
header("Content-Type: application/json");
echo json_encode([
    "sapi" => PHP_SAPI,
    "enabled" => (bool) ini_get("session.upload_progress.enabled"),
    "upload_ok" => isset($_FILES["file"]) &&
        $_FILES["file"]["error"] === UPLOAD_ERR_OK &&
        is_uploaded_file($_FILES["file"]["tmp_name"]) &&
        file_get_contents($_FILES["file"]["tmp_name"]) === "session-upload-smoke",
]);
PHP
    exec apache2-foreground
  ' >/dev/null

  for ((attempt=0; attempt<30; attempt++)); do
    if response="$(docker exec "$container" curl -fsS --max-time 3 http://127.0.0.1/session-probe.php 2>/dev/null)"; then
      ready=1
      break
    fi
    if [[ "$(docker inspect -f '{{.State.Running}}' "$container")" != true ]]; then
      break
    fi
    sleep 1
  done
  if (( ready == 0 )); then
    echo "[$label] Apache did not become ready" >&2
    return 1
  fi
  # Assert web SAPI configuration, rather than inferring it from CLI settings.
  docker exec "$container" php -r '
    $result = json_decode($argv[1], true, 512, JSON_THROW_ON_ERROR);
    if ($result["sapi"] !== "apache2handler" || $result["enabled"] !== ($argv[2] === "1")) {
        fwrite(STDERR, "Unexpected Apache setting: " . $argv[1] . "\n"); exit(1);
    }
  ' -- "$response" "$expected"
  docker exec "$container" php -r '
    if ((bool) ini_get("session.upload_progress.enabled") !== ($argv[1] === "1")) exit(1);
  ' -- "$expected"

  # Multipart upload with the session-progress field must still deliver the file
  # when tracking is disabled. The fixture never invokes WordPress or a database.
  response="$(docker exec "$container" sh -c '
    printf %s session-upload-smoke > /tmp/session-upload-smoke.txt
    curl -fsS --max-time 10 \
      -F PHP_SESSION_UPLOAD_PROGRESS=smoke \
      -F file=@/tmp/session-upload-smoke.txt \
      http://127.0.0.1/session-probe.php
  ')"
  docker exec "$container" php -r '
    $result = json_decode($argv[1], true, 512, JSON_THROW_ON_ERROR);
    if ($result["upload_ok"] !== true) {
        fwrite(STDERR, "File upload failed: " . $argv[1] . "\n"); exit(1);
    }
  ' -- "$response"
  echo "[$label] Apache and CLI setting=$expected; ordinary file upload passed"
  docker rm -f "$container" >/dev/null
}

run_case default 0
run_case disabled 0 -e PHP_SESSION_UPLOAD_PROGRESS_ENABLED=0
run_case enabled 1 -e PHP_SESSION_UPLOAD_PROGRESS_ENABLED=1
run_case empty 0 -e PHP_SESSION_UPLOAD_PROGRESS_ENABLED=

# A typo must stop startup instead of silently removing the mitigation.
container="wazm-session-$$-invalid"
CONTAINERS+=("$container")
docker create --name "$container" -e PHP_SESSION_UPLOAD_PROGRESS_ENABLED=true \
  "$IMAGE" sh -c 'echo UNEXPECTED_COMMAND_EXECUTED' >/dev/null
docker start -a "$container" >/dev/null 2>&1 || true
status="$(docker inspect -f '{{.State.ExitCode}}' "$container")"
logs="$(docker logs "$container" 2>&1)"
if [[ "$status" != 64 || "$logs" != *'must be 0 (disabled) or 1 (enabled)'* || "$logs" == *UNEXPECTED_COMMAND_EXECUTED* ]]; then
  echo "Invalid configuration did not stop startup as expected" >&2
  exit 1
fi
echo "[invalid] Startup rejected an invalid value before running the command"
