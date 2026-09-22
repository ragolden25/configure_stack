#!/bin/bash

POSTGRES18_OUTPUT_DIR="/var/www/html/images/debian13-postgres18"
TAG="$(date +%Y%m%d)"

echo "=== Build debian13-postgres18 image ==="
docker build \
        --add-host=trixie.nuc2.scires.com:192.168.110.213 \
        --no-cache -f "$POSTGRES18_OUTPUT_DIR/Dockerfile.debian13.postgres18" -t container-forge/debian13-postgres18:latest "$POSTGRES18_OUTPUT_DIR"
docker tag container-forge/debian13-postgres18:latest container-forge/debian13-postgres18:"$TAG"

echo "=== Export debian13-postgres18 archives ==="
docker save container-forge/debian13-postgres18:"$TAG" | gzip > "$POSTGRES18_OUTPUT_DIR/debian13-postgres18-$TAG.tar.gz"
docker save container-forge/debian13-postgres18:latest | gzip > "$POSTGRES18_OUTPUT_DIR/debian13-postgres18-latest.tar.gz"

echo "=== Digest & GPG signatures for debian13-postgres18 ==="
sha256sum "$POSTGRES18_OUTPUT_DIR/debian13-postgres18-$TAG.tar.gz" | awk '{print $1}' > "$POSTGRES18_OUTPUT_DIR/digest-$TAG.txt"
sha256sum "$POSTGRES18_OUTPUT_DIR/debian13-postgres18-latest.tar.gz" | awk '{print $1}' > "$POSTGRES18_OUTPUT_DIR/digest-latest.txt"

gpg --batch --yes --pinentry-mode loopback --detach-sign --output "$POSTGRES18_OUTPUT_DIR/debian13-postgres18-$TAG.digest.asc" "$POSTGRES18_OUTPUT_DIR/digest-$TAG.txt"
gpg --batch --yes --pinentry-mode loopback --detach-sign --output "$POSTGRES18_OUTPUT_DIR/debian13-postgres18-latest.digest.asc" "$POSTGRES18_OUTPUT_DIR/digest-latest.txt"
gpg --batch --yes --pinentry-mode loopback --detach-sign --output "$POSTGRES18_OUTPUT_DIR/debian13-postgres18-$TAG.tar.gz.asc" "$POSTGRES18_OUTPUT_DIR/debian13-postgres18-$TAG.tar.gz"
gpg --batch --yes --pinentry-mode loopback --detach-sign --output "$POSTGRES18_OUTPUT_DIR/debian13-postgres18-latest.tar.gz.asc" "$POSTGRES18_OUTPUT_DIR/debian13-postgres18-latest.tar.gz"
