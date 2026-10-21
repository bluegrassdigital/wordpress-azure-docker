# Alternative PHP images checked for BGHT-219

Checked on 21 October 2026; Azure refreshed at 17:11 SAST (15:11 UTC). Tags can move;
the digests below identify the linux/amd64 images inspected at that time.
These checks did not publish images or deploy any sites.

## Findings

| Provider | Evidence | Fit for this container |
| --- | --- | --- |
| [TheCodingMachine](https://github.com/thecodingmachine/docker-images-php) | Disposable containers report PHP 8.3.36 and 8.4.27. The installed CLI **and** `libapache2-mod-php` packages have those patched versions. | A patched Apache mod_php alternative, but requires Dockerfile changes. |
| [Aikido public images](https://gallery.ecr.aws/aikido-dev/php) | Tested Apache tags report 8.3.35 and 8.4.26 and retain the original source tarballs. Build history shows an old-source mod_php build followed by a separate PHP CLI binary overlay. | Apache architecture fits, but the PHP2Shell fix in mod_php is not established by the inspected evidence. |
| [Microsoft App Service](https://mcr.microsoft.com/v2/appsvc/php/tags/list) | Newly published `.5` FPM metadata references the fixed PHP 8.3.36/8.4.27 sources and matching hashes. The Apache tag still references PHP 8.3.9. Binaries were not run. | A patched-source Nginx/FPM alternative, requiring a different process and web-server setup. No suitable Apache base found. |
| [ServerSideUp](https://github.com/serversideup/docker-php/discussions/721) | Current checked 8.3 Bookworm Apache/FPM image metadata reports PHP 8.3.35; maintainers were waiting for the patched official base. | No verified patched candidate, and Apache/FPM needs a different process setup. |

Keep the source-build fallback as the smallest verified change to our
existing Apache/Bookworm container. TheCodingMachine is a separate fallback
option if an integration change becomes necessary.

## TheCodingMachine: patched packages, different layout

The tested images were:

- `thecodingmachine/php:8.3-v5-apache`, amd64 digest
  `sha256:6242242377f0c7fc21fb031547f0509596e753d60fc15a96e6cc3bd010e40d1a`.
  CLI and Apache module package version:
  `8.3.36-1+0~20261021.88+ubuntu24.04~1.gbp250f7c`.
- `thecodingmachine/php:8.4-v5-apache`, amd64 digest
  `sha256:f276ffe66f9ba7d3bba6cc413c04a6d313785d2a58d40fdcfe84082bd99910cd`.
  CLI and Apache module package version:
  `8.4.27-1+0~20261021.57+ubuntu24.04~1.gbp7636b9`.

Both CLI versions were run with networking disabled, a read-only filesystem,
no host mounts and no Linux capabilities. The package database was inspected;
an HTTP WordPress test on these vendor images was not performed.

The [Apache variant](https://github.com/thecodingmachine/docker-images-php/blob/v5/docs/variants.md)
uses mod_php. It uses Ubuntu packages and `/etc/php/<minor>/` rather than the
official image's `/usr/local/etc/php` layout. It does not provide our expected
source tarball or official extension helper commands. Our first PHP ini
installation step and extension build steps would therefore need changes.
Its [extension controls](https://github.com/thecodingmachine/docker-images-php/blob/v5/docs/extensions.md),
runtime user and startup conventions also need an integration review.

## Aikido: verify the Apache module separately

Inspected amd64 digests:

- `public.ecr.aws/aikido-dev/php:8.3.35-apache`:
  `sha256:b080f0c01b6b8e0d69f52992c0a827fda2d9d71f6c2e6d8d463150586758dcd9`.
- `public.ecr.aws/aikido-dev/php:8.4.26-apache`:
  `sha256:51b432c7d5c1039a75e54c95fe3efc54906276b8d5602bdd39895029dee3ff9f`.
- The floating `8.4-apache` tag was also inspected:
  `sha256:3e8e4c38c7fdb95357f0334b94667162075503f732da808076124a6f2883dfac`.

The first two images were run under the same restrictions as the
TheCodingMachine checks. They reported old CLI/php-config versions, and the
retained tarball hashes match the original 8.3.35/8.4.26 releases. Their
OS is Debian 13/Trixie, whereas our existing base is Debian 12/Bookworm. Their
`docker-php-source` helpers extract those tarballs without applying patches.
The inspected image histories compile mod_php using `--with-apxs2`, then
copy a separate `root_binaries/php-cli/<version>/php-cli` binary over the CLI.
No subsequent modification or rebuild of `libphp.so` was visible.

A backport can retain an old version number, so the CLI version alone does
not establish whether that binary has been fixed. The concern is the lack
of evidence for an Apache-module backport. Do not treat a patched CLI as
proof that Apache is patched. Seek patch provenance for mod_php before
using these digests for PHP2Shell remediation.

Aikido's [PHP2Shell announcement](https://www.aikido.dev/blog/critical-vulnerabilities-in-php-php2shell)
names the fixed upstream releases and says further image patches are being
prepared. Its [image service documentation](https://help.aikido.dev/autofix-and-remediation/aikido-images)
distinguishes OS remediation from application-package remediation.

## Azure: new patched FPM images, metadata not a binary test

Checked `mcr.microsoft.com/appsvc/php` images include:

- `8.3-apache_20261021.5.tuxprod`, digest
  `sha256:0c6d42b202fdafb53468929d422830b28b9dcba76ae24525b4d04a41225d0451`,
  source metadata PHP 8.3.9.
- `8.3-fpm_20261021.5.tuxprod`, digest
  `sha256:786a9a4d04c076b3740f9b41b7818c2f7026de0adb86946ddcf338d548bccfc9`,
  source metadata PHP 8.3.36, with the PHP.net tarball hash.
- `8.4-fpm_20261021.5.tuxprod`, digest
  `sha256:25737614e82c6d884fe6ddd81baa72b5880bf8b71dcee58bb94547bed0a00462`,
  source metadata PHP 8.4.27, with the PHP.net tarball hash.

The new FPM images were built around 14:49 UTC and published during this
investigation. Earlier `.2` images referenced 8.3.35/8.4.26; use the exact
new tag and digest when assessing the fixed builds. These are metadata
checks, not CLI or HTTP runtime tests. Microsoft's
[PHP configuration documentation](https://learn.microsoft.com/en-us/azure/app-service/configure-language-php?pivots=platform-linux)
describes the current built-in Nginx setup. Our supervisord configuration
starts Apache and would need changes for an FPM-based runtime.

The other Microsoft-owned repositories checked did not offer a suitable
candidate. `azurelinux/base/php` listed PHP 8.3.35 package tags from
15 October, no 8.4 tags and no verified PHP2Shell backport. Its image is a
package base rather than our Apache web stack. The latest
`appsvc/wordpress-alpine-php` tags were from July 2025.
