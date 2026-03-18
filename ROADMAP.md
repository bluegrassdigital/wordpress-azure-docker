# WordPress Azure Docker Roadmap

This roadmap tracks the next practical steps for `bluegrassdigital/wordpress-azure-sync`.

## Legend

- [ ] To do
- [x] Done

## Now

- [x] Update image names to the Docker Hub repository
  - [x] Replace `yourdockerhub/wordpress-azure` with `bluegrassdigital/wordpress-azure-sync` in `docker-bake.hcl`
  - [x] Set `IMAGE_NAME: bluegrassdigital/wordpress-azure-sync` in `.github/workflows/docker.yml`
- [x] Confirm OCI labels in `Dockerfile`
  - [x] Set `org.opencontainers.image.source` to the Docker Hub repository URL
  - [x] Set `org.opencontainers.image.vendor` to `Bluegrass Digital`
- [x] Add or verify `.dockerignore` to shrink build context while keeping `.github/`
  - [x] Exclude `example/src/**`, `**/.git`, `**/.DS_Store`, `**/node_modules`, `**/.cache`, `**/vendor/*`
- [x] Define the CI tagging policy
  - [x] Push `:8.3-latest` and `:8.4-latest` on every merge to `main` or `master`
  - [x] Only push `:8.x-stable` and full PHP version tags when `github.ref_type == tag`
  - [x] Add a workflow trigger for tag pushes such as `on: push: tags: ['v*']`
- [x] Provide an example Docker Compose setup
  - [x] Default to the Hub image with commented instructions for a local dev build
  - [x] Remove auto-install and keep optional auto-activate
  - [x] Add a manual `wp core install` snippet in `DEV.md`
- [x] Split the documentation by audience
  - [x] Add `DEV.md` for local development, WP-CLI, Xdebug, and the `/home` versus `/homelive` paths
  - [x] Add `OPERATIONS.md` for Azure settings, logs, New Relic, CI tags, and upgrade policy
  - [x] Update the root `README.md` to link to both guides

## Next

- [x] Run a Trivy security scan in CI after pushing images
- [x] Add a weekly scheduled rebuild workflow to pick up base image CVEs
- [ ] Add smoke tests in CI: run the container, `curl http://localhost`, `php -v`, `wp --version`
- [x] Add Dependabot or Renovate for GitHub Actions and base images
- [ ] Add `CHANGELOG.md`, confirm `LICENSE`, and add `CODEOWNERS`
- [x] Define the release process: cut a git tag, then publish `stable` and full PHP version tags
- [ ] Enhance the release workflow with Trivy reports and links to Docker image tags and digests in the GitHub Release body

## Later

- [ ] Add PHP 8.5 targets when it reaches GA
- [ ] Consider dropping supervisor privileges per program where possible
- [ ] Revisit Unison `repeat` versus `fsmonitor` once it is stable on target platforms
- [ ] Add integration tests for the example stack with MySQL and a basic WordPress install
- [ ] Improve the plugin with AJAX log tailing, a settings screen for paths, and basic health checks
- [ ] Write an Azure App Service deployment guide with screenshots

## Operational notes

- Image variants: `8.3`, `8.4`, and `-dev` variants for developer tooling such as Composer and Xdebug; multi-arch on `amd64` and `arm64`
- Sync model: Azure `/home` ↔ `/homelive` via initial `rsync` plus Unison; logs in `/home/LogFiles/sync`
- New Relic: best-effort install controlled through environment variables; document opt-out
