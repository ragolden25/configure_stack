#!/bin/bash

GO_OUTPUT_DIR="/var/www/html/images/debian13-go"
TAG="$(date +%Y%m%d)"

echo "=== Build debian13-go image ==="
docker build \
        --add-host=trixie.nuc2.scires.com:192.168.110.213 \
        --no-cache -f "$GO_OUTPUT_DIR/Dockerfile.debian13.go" -t container-forge/debian13-go:latest "$GO_OUTPUT_DIR"
docker tag container-forge/debian13-go:latest container-forge/debian13-go:"$TAG"

echo "=== Export debian13-go archives ==="
docker save container-forge/debian13-go:"$TAG" | gzip > "$GO_OUTPUT_DIR/debian13-go-$TAG.tar.gz"
docker save container-forge/debian13-go:latest | gzip > "$GO_OUTPUT_DIR/debian13-go-latest.tar.gz"

echo "=== Digest & GPG signatures for debian13-go ==="
sha256sum "$GO_OUTPUT_DIR/debian13-go-$TAG.tar.gz" | awk '{print $1}' > "$GO_OUTPUT_DIR/digest-$TAG.txt"
sha256sum "$GO_OUTPUT_DIR/debian13-go-latest.tar.gz" | awk '{print $1}' > "$GO_OUTPUT_DIR/digest-latest.txt"

gpg --batch --yes --pinentry-mode loopback --detach-sign --output "$GO_OUTPUT_DIR/debian13-go-$TAG.digest.asc" "$GO_OUTPUT_DIR/digest-$TAG.txt"
gpg --batch --yes --pinentry-mode loopback --detach-sign --output "$GO_OUTPUT_DIR/debian13-go-latest.digest.asc" "$GO_OUTPUT_DIR/digest-latest.txt"
gpg --batch --yes --pinentry-mode loopback --detach-sign --output "$GO_OUTPUT_DIR/debian13-go-$TAG.tar.gz.asc" "$GO_OUTPUT_DIR/debian13-go-$TAG.tar.gz"
gpg --batch --yes --pinentry-mode loopback --detach-sign --output "$GO_OUTPUT_DIR/debian13-go-latest.tar.gz.asc" "$GO_OUTPUT_DIR/debian13-go-latest.tar.gz"
