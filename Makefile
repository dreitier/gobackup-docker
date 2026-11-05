IMAGE ?= dreitier/gobackup
TAG ?= local

.PHONY: build hooks lint pin-images

# local image only; releases are published by .github/workflows/release.yml
build:
	docker build -t $(IMAGE):$(TAG) .

hooks:
	pre-commit install

lint:
	pre-commit run --all-files

# pins the base images to their current digests; Dependabot keeps tags and digests up to date afterwards
pin-images:
	.github/scripts/pin-images.py Dockerfile
