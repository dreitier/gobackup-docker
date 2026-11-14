# gobackup Docker image

[![CI](https://github.com/dreitier/gobackup-docker/actions/workflows/ci.yml/badge.svg)](https://github.com/dreitier/gobackup-docker/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/dreitier/gobackup-docker/badge)](https://scorecard.dev/viewer/?uri=github.com/dreitier/gobackup-docker)

[gobackup](https://github.com/gobackup/gobackup) dumps databases and archives folders, then compresses, encrypts and stores the backup in local folders, S3, SFTP, WebDAV and many other storages. The upstream project only publishes the binary; this image adds the client tools gobackup calls, so it can run in Docker or Kubernetes:

- PostgreSQL client (`pg_dump`, `pg_dumpall`) from Fedora, currently version 18
- MariaDB client (`mysqldump`, `mariadb-backup`) for MySQL and MariaDB
- MongoDB Database Tools (`mongodump`), `redis-cli`, `sqlite3`
- `openssl` and all supported compressors (`gzip`/`pigz`, `bzip2`, `xz`, `lzip`, `lzop`, `zstd`, `compress`)

The image is based on Fedora, runs as UID/GID `1000` and is published for `linux/amd64` and `linux/arm64`.

> This repository was called `gobackup-with-interpolator-docker` until 2026-11; [interpolator](https://github.com/dreitier/interpolator) is no longer needed, gobackup expands `${VARS}` in its config itself.

## Getting started
Mount your gobackup configuration to `/etc/gobackup/gobackup.yml`. See the [gobackup documentation](https://gobackup.github.io/) for all options.

- `${VAR}` placeholders in the config are replaced by environment variables, so secrets can be passed as env vars. A `.env` file next to the config is read as well. Unset variables become empty strings.
- `run` (default) starts gobackup in the foreground: it performs the models on their `schedule:` and serves the web UI/API on port `2703` (disable with `web.enabled: false`). Unauthenticated endpoints: `/status` and Prometheus metrics on `/metrics`.
- `perform` backs up all models once and exits (`perform -m <model>` for a single model). Useful for a Kubernetes `CronJob`.
- gobackup keeps its state in `/var/gobackup/.gobackup` (a volume): the retention data that `keep:` uses to delete old backups, and the log shown in the web UI. Mount a persistent volume there when you use `keep:`.

```yaml
# gobackup.yml
models:
  shop:
    schedule:
      cron: "0 3 * * *"
    compress_with:
      type: tgz
    encrypt_with:
      type: openssl
      password: ${ENCRYPTION_PASSWORD}
      args: -pbkdf2 -iter 10000
    databases:
      shop:
        type: postgresql
        host: postgres
        database: shop
        username: shop
        password: ${PG_PASSWORD}
    storages:
      s3:
        type: s3
        bucket: my-backups
        region: eu-central-1
        path: shop
        keep: 14
        access_key_id: ${S3_ACCESS_KEY_ID}
        secret_access_key: ${S3_SECRET_ACCESS_KEY}
```

Scheduled backups:

```bash
docker run -d --name gobackup \
  -v "$PWD/gobackup.yml:/etc/gobackup/gobackup.yml:ro" \
  -v gobackup-state:/var/gobackup/.gobackup \
  -e ENCRYPTION_PASSWORD -e PG_PASSWORD -e S3_ACCESS_KEY_ID -e S3_SECRET_ACCESS_KEY \
  -p 2703:2703 \
  dreitier/gobackup:2
```

The examples use Docker Hub; replace `dreitier/gobackup` with `ghcr.io/dreitier/gobackup` to pull from the GitHub Container Registry.

Single backup:

```bash
docker run --rm -v "$PWD/gobackup.yml:/etc/gobackup/gobackup.yml:ro" -e ... dreitier/gobackup:2 perform
```

Restore an archive encrypted as above: `openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -in backup.tar.gz.enc | tar -xz`

### Registries and tags
Multi-arch images (`linux/amd64`, `linux/arm64`) are published to two registries with the same content and tags:

| Registry                                                                                         | Image                       |
|--------------------------------------------------------------------------------------------------|-----------------------------|
| [Docker Hub](https://hub.docker.com/r/dreitier/gobackup)                                         | `dreitier/gobackup`         |
| [GitHub Container Registry](https://github.com/dreitier/gobackup-docker/pkgs/container/gobackup) | `ghcr.io/dreitier/gobackup` |

```bash
docker pull dreitier/gobackup:2
docker pull ghcr.io/dreitier/gobackup:2
```

| Tag                  | Meaning                                                              |
|----------------------|----------------------------------------------------------------------|
| `2.1.3`, `2.1`, `2`  | version of this image ([Semantic Versioning](https://semver.org/))    |
| `gobackup-v3.1.1`    | latest image containing this gobackup version                        |
| `latest`             | latest release                                                       |

The image has its own version. Upgrading gobackup to a new minor version is a minor release of the image, a new major version of gobackup is a major release. Base image and package updates are patch releases. The contained gobackup version is also in the label `com.dreitier.gobackup.version`.

### Upgrading from the images before 2.0.0
Images up to `20260514-dreitier` and the `*-huacnlee`/`*-dreitier` tags were built with gobackup 1.x/3.0 and interpolator.

- The config is now mounted directly to `/etc/gobackup/gobackup.yml` instead of `/etc/gobackup/config-raw.yaml`; `${VAR}` placeholders keep working.
- `cron "<expression>"` arguments are gone: put a `schedule:` into the model and use the default `run` command, or run `perform` from a Kubernetes `CronJob`.
- The container runs as UID `1000` instead of root; mounted folders it writes to (local storage, `workdir`) must be writable for it.
- The `*-dreitier` images from 2022 encrypted with `-pbkdf2 -iter 10000` by default. gobackup 3 doesn't, so add `args: -pbkdf2 -iter 10000` to `encrypt_with` if you want new backups to decrypt with the same command as the old ones.
- Check the [gobackup changelog](https://github.com/gobackup/gobackup/releases) for config changes between 1.x and 3.x.

### Verifying images
Images in both registries are signed keyless with [Sigstore](https://www.sigstore.dev/); the signatures are bound to the identity of the release workflow in this repository:

```bash
cosign verify ghcr.io/dreitier/gobackup:2 \
  --certificate-identity "https://github.com/dreitier/gobackup-docker/.github/workflows/release.yml@refs/heads/main" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

They also come with [build provenance attestations](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations) and an SBOM:

```bash
gh attestation verify oci://ghcr.io/dreitier/gobackup:2 --owner dreitier
gh attestation verify oci://index.docker.io/dreitier/gobackup:2 --owner dreitier
```

The gobackup binary is downloaded from the upstream release and verified against the SHA-256 checksums pinned in the [Dockerfile](Dockerfile).

## Development
- `make build` builds the image locally, `make lint` runs the pre-commit hooks (actionlint, hadolint), `make hooks` installs them.
- CI ([ci.yml](.github/workflows/ci.yml)) builds the multi-arch image, checks that all client tools are present, runs an end-to-end backup (PostgreSQL dump + folder archive, compressed, encrypted, stored locally, then decrypted and checked), checks that `run` stays in the foreground and scans the image with Trivy.
- [update-gobackup.yml](.github/workflows/update-gobackup.yml) opens a PR when a new gobackup version is released; Dependabot updates the base images, actions and release tooling.

### Creating new releases
Releases are fully automated with [semantic-release](https://github.com/semantic-release/semantic-release). Every push to `main` runs the [release workflow](.github/workflows/release.yml): after CI passes, the next version is derived from the [Conventional Commits](https://www.conventionalcommits.org/) since the last release, `CHANGELOG.md` is updated, a GitHub release is created and the image is published to Docker Hub and GHCR.

| Commit / PR title                                  | Release                   |
|----------------------------------------------------|---------------------------|
| `fix: ...`, `perf: ...`, `build(deps): ...`        | patch (`1.0.0` → `1.0.1`) |
| `feat: ...`                                        | minor (`1.0.0` → `1.1.0`) |
| `feat!: ...` or a `BREAKING CHANGE:` footer        | major (`1.0.0` → `2.0.0`) |
| `docs:`, `ci:`, `chore:`, `refactor:`, `test:` ... | no release                |

PRs are squash-merged, so the **PR title** becomes the commit message on `main`; a check on every PR makes sure it follows the Conventional Commits format. Don't edit `CHANGELOG.md` or create tags by hand.

## Support
This software is provided as-is. You can open an issue in GitHub's issue tracker at any time. But we can't promise to get it fixed in the near future.
If you need professional support, consulting or a dedicated feature, please get in contact with us through our [website](https://dreitier.com).

## License
This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.
