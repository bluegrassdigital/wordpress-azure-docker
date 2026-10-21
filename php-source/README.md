# Emergency PHP source builds (BGHT-219)

PHP 8.3.36 and 8.4.27 address CVE-2026-109618 and CVE-2026-109619.
The [PHP security advisory](https://www.php.net/archive/2026.php) includes
Apache mod_php among the affected runtimes. This fallback lets us build
patched WordPress images while Docker's official images are being published.
See [the alternative-image checks](ALTERNATIVES.md) for Aikido, Azure and
other vendor images inspected during the incident.
See [local validation results](VALIDATION.md) for built image IDs, passed
checks and limitations.

The `8.3/` and `8.4/` directories are unchanged copies of the official
Apache/Bookworm recipes and all seven files in each recipe directory from
[docker-library/php commit f6048b5f6e3c2202ee082665a4ccc0d90de291a3](https://github.com/docker-library/php/tree/f6048b5f6e3c2202ee082665a4ccc0d90de291a3).
The upstream license is included. `SHA256SUMS` records these vendored files;
check it from the repository root with `shasum -a 256 -c php-source/SHA256SUMS`.

These recipes came from [upstream PR 1694](https://github.com/docker-library/php/pull/1694),
which merged on 21 October 2026 while this fallback was being prepared.
Both Apache/Bookworm GitHub CI jobs passed for this commit. The release
tarball hashes were also checked against PHP.net's release metadata:

| PHP | Tarball SHA256 | Release metadata |
| --- | --- | --- |
| 8.3.36 | `dd54693aa334c5c4d72e9aee96b082c2473750a18a6c1d105789c93a3b1692fd` | [PHP.net](https://www.php.net/releases/index.php?json&version=8.3.36) |
| 8.4.27 | `dcf93923b0e38e0d5252b25b796520b5a47761a08b3488b6d0b5d1115764d3f0` | [PHP.net](https://www.php.net/releases/index.php?json&version=8.4.27) |

The recipes verify both the tarball checksum and its GPG signature. They
compile Apache mod_php with `apache2-dev` and `--with-apxs2`, then install
the CLI, Apache module, headers and extension build tools. They retain
`/usr/src/php.tar.xz`, so the WordPress image compiles its bundled extensions
from the patched source. Do not substitute a CLI-only rebuild.

The emergency Bake file also pins Imagick 3.8.0 to its
[upstream release commit](https://github.com/Imagick/imagick/commit/555bf68b592a8d9d0a0a2f37d1256a8b6cf2d39e).
The first runtime build received HTTP 500 from PECL's Imagick archive
endpoint. The installer supports building from a GitHub commit, so this
uses the same release through its upstream repository. The ordinary
Dockerfile's Imagick package default is unchanged.

## Build locally

Run these commands from the repository root. The separate Bake file builds
the PHP bases before the WordPress extensions through BuildKit target
contexts. It uses local test tags and defaults to `linux/amd64` for Azure.

```sh
docker buildx bake -f docker-bake.emergency.hcl --load
docker buildx bake -f docker-bake.emergency.hcl emergency83-dev emergency84-dev --load

bash scripts/smoke-test-php.sh wordpress-azure-emergency:8.3.36-emergency-source-local 8.3.36
bash scripts/smoke-test-php.sh wordpress-azure-emergency:8.4.27-emergency-source-local 8.4.27
bash scripts/smoke-test-php.sh wordpress-azure-emergency:8.3.36-dev-emergency-source-local 8.3.36 dev
bash scripts/smoke-test-php.sh wordpress-azure-emergency:8.4.27-dev-emergency-source-local 8.4.27 dev
```

To load and inspect the source bases separately:

```sh
docker buildx bake -f docker-bake.emergency.hcl source83 source84 --load
bash scripts/smoke-test-php.sh wordpress-azure-php-source:8.3.36 8.3.36 base
bash scripts/smoke-test-php.sh wordpress-azure-php-source:8.4.27 8.4.27 base
```

The smoke test checks the exact CLI and HTTP PHP versions, Apache's PHP
handler and prefork module, required extensions, and the normal startup
path with sync enabled and disabled. WordPress core download requires
network access. A PHP probe does not need a database; a full WordPress
installation test needs a disposable database.

## Multiarch and publication

The official architecture handling is retained. To build both architectures
without publishing, export an OCI archive:

```sh
PHP_SOURCE_PLATFORMS='linux/amd64,linux/arm64' \
  docker buildx bake -f docker-bake.emergency.hcl emergency83 \
  --set 'emergency83.output=type=oci,dest=/tmp/wordpress-emergency83.tar'
```

Repeat for `emergency84` with a separate output path. Validate each
architecture before publication. Local amd64 testing on Apple Silicon uses
emulation; it does not prove native Azure performance or arm64 behavior.

This fallback does not change the publishing workflow or ordinary Bake
targets. Do not combine the two Bake files. Publication, production tags
and Azure deployments require separate coordination with the operator;
the existing watcher may still build `master` once Docker publishes both
patched official bases.

Every fallback application tag includes `emergency-source`, including dev
images. For a later approved publication, set `EMERGENCY_IMAGE` to the
destination repository and `EMERGENCY_BUILD_ID` to a unique timestamp and
commit, such as `20261021160000-a1b2c3d4e5f6`. This produces tags such as
`8.3.36-emergency-source-20261021160000-a1b2c3d4e5f6`. Use the WordPress
repository's build commit in real tags. Keep normal `latest`, `stable`,
timestamped stable and plain PHP-version tags for the official-base build.
After those images pass the same checks, switch each site's image reference
to its normal immutable release tag.

The vendored recipes pin PHP source and recipe content. Debian packages,
the Debian base tag and existing WordPress tooling downloads remain mutable,
as in the normal build. This is not a fully reproducible image build.

## Return to published bases

Use the ordinary build path after verifying Docker's base tags:

```sh
docker build --platform linux/amd64 --target runtime --build-arg PHP_VERSION=8.3 .
docker build --platform linux/amd64 --target runtime --build-arg PHP_VERSION=8.4 .
```

`PHP_BASE_IMAGE` defaults to the existing official Apache/Bookworm reference.
Only the emergency Bake file overrides it. Remove the emergency Bake file
and `php-source/` once the fallback is retired.
