# syntax=docker/dockerfile:1

# gobackup is built from source instead of using the upstream release binary, which is built with an old Go
# and outdated dependencies. gobackup/go.mod pins the gobackup commit (updated together with GOBACKUP_VERSION
# by .github/workflows/update-gobackup.yml) and the versions of all dependencies (updated by Dependabot).
# The build stages run on the build platform and cross-compile; only the runtime image needs emulation.

# gobackup source and all modules from the Go module proxy, verified against gobackup/go.sum
FROM --platform=$BUILDPLATFORM golang:1.27-alpine@sha256:70bd7ddea8b6cbe5d6943cde279d6b67feb10cc924fb9100d1d8757c1575b280 AS source

# never download another Go toolchain; the image must satisfy the go directive in gobackup/go.mod
ENV GOTOOLCHAIN=local
WORKDIR /build
COPY gobackup/go.mod gobackup/go.sum ./
RUN go mod download \
    && cp -R "$(go list -m -f '{{.Dir}}' github.com/gobackup/gobackup)" /src \
    && chmod -R u+w /src

# web UI, embedded into the binary (upstream builds it before `go build` as well, it's not in the Go module)
FROM --platform=$BUILDPLATFORM node:24-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS web

# upstream maintains yarn.lock (its package-lock.json is out of date and fails `npm ci`);
# yarn 1 via corepack, pinned by version and hash
ARG YARN=yarn@1.22.22+sha512.a6b2f7906b721bba3d67d4aff083df04dad64c399707841b7acf00f6b133b7ac24255f2652fa22ae3534329dc6180534e98d17432037ff6fd140556e2bb3137e
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
WORKDIR /src/web
COPY --from=source /src/web ./
# git: yarn.lock pins one dependency (react-virtualized-fixed-import) to a GitHub commit
# DL3018: build-only tool, not part of the published image
# hadolint ignore=DL3018
RUN apk add --no-cache git \
    && corepack "${YARN}" install --frozen-lockfile --non-interactive --no-progress \
    && corepack "${YARN}" build

FROM source AS build

ARG TARGETOS
ARG TARGETARCH
# release tag of the commit pinned in gobackup/go.mod; updated by .github/workflows/update-gobackup.yml,
# read by the release workflow for the image tag gobackup-vX.Y.Z and the label com.dreitier.gobackup.version
ARG GOBACKUP_VERSION=v3.1.1

COPY --from=web /src/web/dist /src/web/dist
# build gobackup from the copy that contains the web UI, with the dependency versions of gobackup/go.mod;
# same flags as upstream's goreleaser config (version without the leading v)
RUN go mod edit -replace github.com/gobackup/gobackup=/src \
    && CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
       go build -mod=readonly -trimpath -ldflags "-s -w -X main.version=${GOBACKUP_VERSION#v}" \
         -o /out/gobackup github.com/gobackup/gobackup

# Runtime image: gobackup plus the client tools it shells out to (dump tools, compressors, openssl).
# Fedora instead of Alpine: current PostgreSQL client from Fedora itself (PGDG has no Fedora aarch64 packages),
# MongoDB ships RHEL packages that work on Fedora.
FROM fedora:45@sha256:a7d72ba2745b100a3351087472e5ee7b2450af7cf331e7673007e3817612839c

LABEL org.opencontainers.image.source="https://github.com/dreitier/gobackup-docker" \
      org.opencontainers.image.description="gobackup with database client tools (PostgreSQL, MySQL/MariaDB, MongoDB, Redis, SQLite)" \
      org.opencontainers.image.licenses="MIT"

COPY mongodb.repo /etc/yum.repos.d/mongodb.repo

# postgresql: client tools of Fedora's default major version (18 on Fedora 44); pg_dump must not be older
# than the server – raise the Fedora release (or switch to a versioned postgresqlNN package) for newer servers
# curl, sed: not used by gobackup itself, but by restore scripts running in this image (download a backup,
# filter a SQL dump before piping it to psql); installed explicitly instead of relying on the base image
# DL3041: distribution packages are not pinned; the image is rebuilt on every release and weekly in CI
# hadolint ignore=DL3041
RUN dnf install -y --setopt=install_weak_deps=False \
      postgresql \
      mariadb \
      mariadb-backup \
      mongodb-database-tools \
      redis \
      sqlite \
      openssl \
      ca-certificates \
      tzdata \
      coreutils \
      curl \
      sed \
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
ENV HOME=/var/gobackup \
    GOBACKUP_DIR=/var/gobackup/.gobackup

RUN groupadd -g 1000 gobackup \
    && useradd -g gobackup -u 1000 -m -d /var/gobackup -s /sbin/nologin gobackup \
    && mkdir -p /etc/gobackup /var/gobackup/.gobackup \
    && chown gobackup:gobackup /var/gobackup/.gobackup

COPY --from=build /out/gobackup /usr/local/bin/gobackup

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
