# Local validation — BGHT-219

Tested on 21 October 2026 on Docker Desktop 4.88.1, using `linux/amd64`
images under emulation on an Apple Silicon host.

The source recipes are pinned to
`docker-library/php@f6048b5f6e3c2202ee082665a4ccc0d90de291a3`.
Both builds passed the official recipe's PHP tarball SHA256 and GPG checks.
All vendored file checksums passed too.

## Built images

These are local image/config IDs, not published registry manifest digests.

| Local image | Image ID (sha256) |
| --- | --- |
| `wordpress-azure-php-source:8.3.36` | `acfcb87042d73d343bb81783cc027f3f305db5df35a7bf8f4c59bd701d03a370` |
| `wordpress-azure-php-source:8.4.27` | `dde1cf392e6c41fd99d6d6c3e551f441cdff2967cd9dd8e82427a079781fa249` |
| `wordpress-azure-emergency:8.3.36-emergency-source-local` | `baf5e6eccacfd742d88d5236da1017e339d94fcffcdc58ad25373aaaa01acc51` |
| `wordpress-azure-emergency:8.4.27-emergency-source-local` | `8ff78a2910817f4aeb66417642f82672492b25b9845dada59fcda52f9273c2fb` |
| `wordpress-azure-emergency:8.3.36-dev-emergency-source-local` | `87a3b989b356dbce42b2febdbd57a5aff86ae458b2d6fadd3c892c717153a293` |
| `wordpress-azure-emergency:8.4.27-dev-emergency-source-local` | `df39339e00830bc5f97ed9e26418a165ae255755055eba056e06a00af052229f` |

All six images report architecture `amd64`. Build commands:

```sh
docker buildx bake -f docker-bake.emergency.hcl source83 source84 --load
docker buildx bake -f docker-bake.emergency.hcl all --load
```

The first application build failed when PECL returned HTTP 500 for
`imagick-3.8.0.tgz`. The successful retry used the same Imagick release
through its pinned upstream GitHub commit, as described in the runbook.

## Passed checks

- Both source bases passed `scripts/smoke-test-php.sh` in `base` mode.
- All four WordPress images passed that script in `runtime` or `dev` mode.
  Each image passed normal entrypoint startup with sync enabled and disabled.
- CLI, `php-config`, installed PHP headers and HTTP each reported the exact
  expected PHP patch version. HTTP reported `PHP_SAPI=apache2handler`.
- Retained `/usr/src/php.tar.xz` hashes matched the pinned PHP.net hashes.
- Apache configuration syntax and PHP/prefork modules passed. WordPress
  images also had rewrite, expires, headers and remoteip enabled.
- Required extensions loaded in CLI and Apache: APCu, bcmath, exif, GD,
  MySQLi, ZIP, OPcache, SOAP, PDO, PDO MySQL and Imagick. Dev checks also
  verified Xdebug. The builds installed Imagick 3.8.0 and Xdebug 3.5.3.
- Fresh WordPress 7.1.3 core and configuration files were bootstrapped in
  both storage modes.
- Both production images installed WordPress against a disposable MySQL
  8.4 database, passed `wp core is-installed`, and served the homepage and
  login page through Apache. The database, network and containers were
  removed after testing; no Azure site was contacted.
- A negative check rejected the existing PHP 8.3.35 base when 8.3.36 was
  required.
- Docker's ordinary build check with `PHP_VERSION=8.4` passed without
  warnings. Bake plans were checked for all four prod/dev targets, their
  source-base dependencies, separate emergency tags and multiarch OCI output.

Raw logs from this session are in `/tmp/php-emergency-*-smoke.log`,
`/tmp/php-emergency-wordpress-test.log` and
`/tmp/php-emergency-tagged-build-retry.log`. They are temporary local files.

## Limits and remaining findings

The existing `scripts/smoke-test.sh` failed on both production images
because `/homelive/LogFiles/sync/apache2/error.log` did not exist after its
120-second wait. The same test reproduced the identical failure on the
pre-existing local `bluegrassdigital/wordpress-azure-sync:8.4-dev-stable`
image.

During the baseline run, sync-init was still copying WordPress from the
host-mounted `/home` into `/homelive`. Apache's active error log was still
under `/home`; init had not reached its config rewrite and Apache restart.
The test's `sync-init.current.log` symlink appears at the start of init, so
its existence does not indicate completed initialization. This is an
existing readiness/timeout issue under the Mac host bind mount. No logging
configuration was changed for this fallback. The new PHP smoke test uses
named volumes and waits for the init completion marker; all four images
passed both storage modes. The database-backed WordPress HTTP tests passed
too. The older test should wait for initialization before checking the
final log path.

Arm64 builds and native Azure performance were not tested. The retained
official recipes and Bake platform selection support arm64, and the
two-platform OCI build plan was checked without executing that build.

Existing `.github/workflows/docker.yml` and `docker-bake.hcl` publishing
edits were preserved byte for byte. No images were pushed, publishing
workflow dispatched, branches merged or Azure sites deployed.
