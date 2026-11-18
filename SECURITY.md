# Security policy

## Supported versions

Only the latest release of the image (tag `latest` and the highest `X.Y.Z`) gets security fixes. Fixes are
released as new image versions; older tags are not rebuilt. The image is rebuilt and scanned with
[Trivy](https://trivy.dev/) on every release and weekly in CI, Dependabot keeps the base images and the Go
modules gobackup is built with up to date.

## Reporting a vulnerability

Please **don't open a public issue**. Report vulnerabilities privately through GitHub:
[Report a vulnerability](https://github.com/dreitier/gobackup-docker/security/advisories/new)
(Security tab → "Report a vulnerability").

Please include the image tag or digest, how to reproduce the issue and its impact. We'll get back to you
in the advisory, keep you updated on the fix and credit you in the advisory unless you'd rather not be
named.

## Scope

This repository builds the Docker image: the Dockerfile, the build of gobackup from source and the
client tools installed into the image. Please report vulnerabilities in

- **gobackup itself** to the [gobackup project](https://github.com/gobackup/gobackup/security),
- **Fedora packages** (PostgreSQL, MariaDB, Redis, OpenSSL, ...) to [Fedora](https://fedoraproject.org/wiki/Security_Bugs),
- **the MongoDB Database Tools** to [MongoDB](https://www.mongodb.com/docs/manual/tutorial/create-a-vulnerability-report/).

We pick up their fixes with the next image release. If a vulnerability in one of them is exploitable
because of how this image is built or configured, report it here.
