#!/bin/bash
set -euo pipefail

ROOT="/opt/ansible/staged/postgres"
SCRIPTS="$ROOT/scripts"

VERSION="${1:-$("$SCRIPTS/detect_postgres_version.sh")}"

echo "Staging PostgreSQL $VERSION"

DEST="$ROOT/$VERSION"
SRC="$DEST/src"
STAGED="$DEST/staged"
LOGS="$DEST/logs"

mkdir -p "$SRC" "$STAGED" "$LOGS"

# Write inventory.env
cat > "$DEST/inventory.env" <<EOF
POSTGRES_VERSION=$VERSION
STAGED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

cp "$DEST/inventory.env" "$ROOT/inventory.env"

# Download source
(
    cd "$SRC"
    wget -q -O postgresql.tar.gz \
        "https://ftp.postgresql.org/pub/source/v${VERSION}/postgresql-${VERSION}.tar.gz"
    tar -xf postgresql.tar.gz
) | tee "$LOGS/download.log"

# Build
(
    cd "$SRC/postgresql-${VERSION}"

    ./configure \
        --prefix="/opt/postgresql/${VERSION}" \
        --with-gssapi \
        --with-icu \
        --with-ldap \
        --with-libcurl \
        --with-libnuma \
        --with-liburing \
        --with-libxml \
        --with-libxslt \
        --with-llvm \
        --with-lz4 \
        --with-pam \
        --with-selinux \
        --with-ssl=openssl \
        --with-uuid=e2fs \
        --with-zstd \
        --with-system-tzdata=/usr/share/zoneinfo

    make world-bin -j"$(nproc)"
    make install-world-bin DESTDIR="$STAGED"
) | tee "$LOGS/build.log"

# Adjust listen_addresses
sed -E -i \
  -e "s|^#?(listen_addresses)\s*=\s*\S+.*|\1 = '*'|" \
  "$STAGED/opt/postgresql/${VERSION}/share/postgresql.conf.sample"

echo "PostgreSQL $VERSION staged successfully."
