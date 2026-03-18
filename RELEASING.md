# Releasing

This document explains how images are tagged, how releases are cut, and how changelogs are maintained.

## Tag summary

- **Moving tags**: `:8.3-latest`, `:8.4-latest`, `:8.3-dev-latest`, `:8.4-dev-latest`, `:8.3-dev-stable`, `:8.4-dev-stable`, `:8.x-stable`
- **Immutable production tags**: `:8.3-stable-<YYYYMMDDHHMMSS>`, `:8.4-stable-<YYYYMMDDHHMMSS>`, and full PHP engine tags such as `:8.3.11`
- **Dev image tags**: moving tags like `-dev-latest` and `-dev-stable`; there are no per-build dev tags

CI sets `BUILD_DATE=$(date +%Y%m%d%H%M%S)` to create the timestamp suffix.

Production users should pin to immutable tags or digests. Moving tags are for convenience.

## Release cadence

### Weekly maintenance release

A scheduled CI job rebuilds images to pick up upstream security and OS updates.

Expected results:

- fresh `:8.x-latest` tags
- fresh `:8.x-dev-latest` tags
- fresh `:8.x-dev-stable` tags
- fresh immutable `:8.x-stable-<YYYYMMDDHHMMSS>` tags
- an updated moving `:8.x-stable` tag for each supported minor version

### Feature release

When notable changes land, cut a repository tag such as `v2025.08.21` or `v1.2.0`.

Expected results:

- new multi-architecture images
- updated `:8.x-stable` tags
- full PHP engine tags such as `:<full-php-version>` and `:<full-php-version>-dev`
- a GitHub Release built from the matching changelog entry

Even here, production should still pin to immutable tags.

## Changelog workflow

`CHANGELOG.md` is the source of truth.

1. Keep the `Unreleased` section current while work is in progress.
2. On a feature release, move those entries into a new dated or semver section.
3. Tag the repo and publish a GitHub Release using the same notes.

## Tagging procedures

### Weekly maintenance

CI handles this flow:

- build prod and dev images for each supported PHP minor version
- publish `:8.x-latest` and `:8.x-dev-latest`
- publish date-stamped tags `:8.x-stable-<YYYYMMDDHHMMSS>`
- update `:8.x-stable` and `:8.x-dev-stable` to the newest weekly build

### Feature release

1. Update `CHANGELOG.md` by moving `Unreleased` items into a new release section.
2. Tag the repository:

```bash
git tag -a vYYYY.MM.DD -m "Release vYYYY.MM.DD"
git push --tags
```

3. Let CI build the multi-arch images, update `:8.x-stable`, and create the full PHP version tags.
4. Publish a GitHub Release from the changelog section.

## Rollback guidance

Roll back to a previously validated immutable tag such as `:8.x-stable-<YYYYMMDDHHMMSS>` or to a pinned digest.

Do not rely on moving tags like `:latest` or `:stable` for rollback.

## Notes

- `:8.x-stable` is convenient for non-production use, but it is still a moving tag.
- CI includes Trivy scanning.
- Security posture depends mainly on weekly rebuilds and upstream patches.
