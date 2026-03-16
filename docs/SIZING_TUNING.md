# Sizing & Tuning

This image standardizes on Apache `mpm_event` + PHP‑FPM. Defaults are safe and self‑tuning; a few environment variables allow advanced tuning. On first boot, the container logs the detected memory limit and the computed `pm.max_children`.

## Quick knobs
- `DOCKER_SYNC_ENABLED`: `0|1`. When `1`, the site serves from `/homelive` with Unison syncing to `/home` (faster for Azure Files). When `0`, serves directly from `/home`.
- `PHP_FPM_MAX_CHILDREN`: Override the auto‑tuned `pm.max_children`.
- `PHP_CHILD_MB`: Estimated RSS per FPM child in MB (default `48`). Used for auto‑tuning.
- `PHP_FPM_MAX_REQUESTS`: Recycle workers after N requests (default `1000`).
- `APACHE_KEEPALIVE_TIMEOUT`: Keep‑alive seconds (default `2`).
- `APACHE_MAX_KEEPALIVE_REQUESTS`: Requests per keep‑alive connection (default `100`).
- `APACHE_PROXY_TIMEOUT`: Proxy timeout to FPM in seconds (default `120`).
- `PHP_OPCACHE_MB`: OPcache memory (default `192`).
- `PHP_OPCACHE_MAX_FILES`: OPcache max accelerated files (default `100000`).
- `PHP_OPCACHE_REVALIDATE_SEC`: OPcache revalidate frequency (default `2`).

## Auto‑tuning formula
- Detect memory limit from cgroup v2 (`/sys/fs/cgroup/memory.max`), v1, or fall back to `MemTotal`.
- Reserve headroom: `max(1024 MB, 15% of limit)`.
- Assume per‑child RSS `PHP_CHILD_MB` (default `48`).
- If `PHP_FPM_MAX_CHILDREN` is unset, compute:
  - `pm.max_children = clamp(floor((limitMB − headroomMB)/childMB), 50, 800)`

The container logs the chosen value at startup.

## Health endpoints
- `GET /healthz`: 200 OK when PHP‑FPM responds to ping (use for App Service Health check).
- `GET /ping` and `GET /status`: available locally only.

## Sensible defaults
- Apache: `KeepAlive On`, `KeepAliveTimeout 2s`, `MaxKeepAliveRequests 100`.
- PHP‑FPM: `pm=dynamic`, `pm.max_requests=1000`, `request_terminate_timeout=120s`.
- OPcache: enabled with memory and file limits above; revalidate every 2s.

## Notes
- For short, spiky latency, the event+FPM model yields more headroom under keep-alive and avoids immediate 5xx bursts; queues build in FPM first.
- This image no longer uses mod_php; typical WordPress setups require no changes (backwards compatible for common .htaccess and plugin patterns).
