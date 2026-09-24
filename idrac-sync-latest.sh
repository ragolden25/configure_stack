#!/usr/bin/env bash
set -euo pipefail

COMPONENT="idrac"
STAGED_ROOT="/opt/ansible/staged/${COMPONENT}"
BUILD_ROOT="/opt/ansible/build/grafana_stack/${COMPONENT}"

QUARTER_FILE="/opt/ansible/build/current_quarter"

if [[ ! -f "${QUARTER_FILE}" ]]; then
  echo "ERROR: Quarter file missing: ${QUARTER_FILE}" >&2
  exit 1
fi

QUARTER="$(cat "${QUARTER_FILE}")"

# ------------------------------------------------------------
# VERSION INPUT (falls back to detection against staged/ when no
# argument is given; pass a version explicitly to sync/revert to a
# specific staged version)
# ------------------------------------------------------------
if [[ $# -ge 1 ]]; then
    VERSION="$1"
    echo "Version argument given: ${VERSION}"
else
    VERSION="$(/opt/ansible/build/grafana_stack/idrac/scripts/detect_idrac_version.sh)"

    if [[ -z "${VERSION}" ]]; then
        echo "ERROR: No staged versions found in ${STAGED_ROOT}" >&2
        exit 2
    fi

    echo "No version argument given; detected latest staged version: ${VERSION}"
fi

SRC_STAGED="${STAGED_ROOT}/${VERSION}/staged"
SRC_INV="${STAGED_ROOT}/${VERSION}/inventory.env"

DEST_STAGED="${BUILD_ROOT}/${QUARTER}/staged"
DEST_INV="${BUILD_ROOT}/${QUARTER}/inventory.env"

# ------------------------------------------------------------
# VALIDATE SOURCE
# ------------------------------------------------------------
if [[ ! -d "${SRC_STAGED}" ]]; then
    echo "ERROR: staged directory missing: ${SRC_STAGED}" >&2
    exit 3
fi

if [[ ! -f "${SRC_INV}" ]]; then
    echo "ERROR: inventory.env missing: ${SRC_INV}" >&2
    exit 4
fi

# ------------------------------------------------------------
# SYNC
# ------------------------------------------------------------
echo "Syncing iDRAC ${VERSION} into quarter ${QUARTER}"

rm -rf "${DEST_STAGED}"
mkdir -p "${DEST_STAGED}"

# Copy staged runtime artifacts
rsync -a "${SRC_STAGED}/" "${DEST_STAGED}/"

# Copy inventory.env INTO THE STAGED DIRECTORY (required by build roles)
cp "${SRC_INV}" "${DEST_STAGED}/inventory.env"

# Also copy inventory.env to quarter root (optional but harmless)
cp "${SRC_INV}" "${DEST_INV}"

echo "Sync complete for iDRAC ${VERSION} into quarter ${QUARTER}"
