# syntax=docker/dockerfile:1

# Downloads the official gobackup release binary (static, CGO disabled) and verifies its checksum.
# Runs on the build platform; only the download depends on the target platform.
FROM --platform=$BUILDPLATFORM alpine:3.23 AS gobackup

ARG TARGETARCH
# updated by .github/workflows/update-gobackup.yml, checksums from gobackup_<version>_checksums.txt of the release
ARG GOBACKUP_VERSION=v3.1.1
ARG GOBACKUP_SHA256_AMD64=d4ec264c2f266742aa370e90a1666535917de0207bd908786823415fce4924c6
ARG GOBACKUP_SHA256_ARM64=517eda21d4e56e0faa0e15c110d395d83fe987bfce26eaab81cee81fe55ff9f8

SHELL ["/bin/ash", "-euo", "pipefail", "-c"]
WORKDIR /download
RUN case "${TARGETARCH}" in \
      amd64) sha256="${GOBACKUP_SHA256_AMD64}" ;; \
      arm64) sha256="${GOBACKUP_SHA256_ARM64}" ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && wget -q -O gobackup.tar.gz "https://github.com/gobackup/gobackup/releases/download/${GOBACKUP_VERSION}/gobackup-linux-${TARGETARCH}.tar.gz" \
    && echo "${sha256}  gobackup.tar.gz" | sha256sum -c - \
    && tar -xzf gobackup.tar.gz gobackup

# Runtime image: gobackup plus the client tools it shells out to (dump tools, compressors, openssl).
# Fedora instead of Alpine because PostgreSQL (PGDG) and MongoDB ship current client packages for it.
FROM fedora:44

# major version of the PostgreSQL client tools; pg_dump must not be older than the server
ARG PG_MAJOR=18

LABEL org.opencontainers.image.source="https://github.com/dreitier/gobackup-with-interpolator-docker" \
      org.opencontainers.image.description="gobackup with database client tools (PostgreSQL, MySQL/MariaDB, MongoDB, Redis, SQLite)" \
      org.opencontainers.image.licenses="MIT"

COPY mongodb.repo /etc/yum.repos.d/mongodb.repo

# DL3041: distribution packages are not pinned; the image is rebuilt on every release and weekly in CI
# hadolint ignore=DL3041
RUN dnf install -y --setopt=install_weak_deps=False \
      "https://download.postgresql.org/pub/repos/yum/reporpms/F-$(rpm -E %fedora)-$(uname -m)/pgdg-fedora-repo-latest.noarch.rpm" \
    && dnf install -y --setopt=install_weak_deps=False \
      "postgresql${PG_MAJOR}" \
      mariadb \
      mariadb-backup \
      mongodb-database-tools \
      redis \
      sqlite \
      openssl \
      ca-certificates \
      tzdata \
      coreutils \
      tar \
      gzip \
      pigz \
      bzip2 \
      xz \
      lzip \
      lzop \
      zstd \
      ncompress \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/cache/libdnf5 /var/log/dnf*

# gobackup keeps its state (retention/cycler data, log, pid) in $GOBACKUP_DIR; mount a volume there,
# otherwise `keep:` can't remove old backups after a container restart.
ENV PATH="/usr/pgsql-${PG_MAJOR}/bin:${PATH}" \
    HOME=/var/gobackup \
    GOBACKUP_DIR=/var/gobackup/.gobackup

RUN groupadd -g 1000 gobackup \
    && useradd -g gobackup -u 1000 -m -d /var/gobackup -s /sbin/nologin gobackup \
    && mkdir -p /etc/gobackup /var/gobackup/.gobackup \
    && chown gobackup:gobackup /var/gobackup/.gobackup

COPY --from=gobackup /download/gobackup /usr/local/bin/gobackup

USER 1000:1000
WORKDIR /var/gobackup
VOLUME ["/var/gobackup/.gobackup"]
# web UI/API, if enabled in the config (web:)
EXPOSE 2703/tcp

# The config is read from /etc/gobackup/gobackup.yml (mount it there); ${VARS} in it are expanded from the
# environment and from a .env file next to it.
# `run` starts the scheduler (and web UI) in the foreground; `perform` runs all models once and exits.
ENTRYPOINT ["/usr/local/bin/gobackup"]
CMD ["run"]
