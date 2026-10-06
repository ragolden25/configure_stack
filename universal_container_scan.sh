#!/usr/bin/env bash

set -euo pipefail

# ===================================================================
# Universal Container Scan Pipeline
# SBOM → Vulnerability → Compensating Control Verification → OpenSCAP
# ===================================================================

# ---------------------------------------------------------------
# Argument Parser (positional only)
# ---------------------------------------------------------------
IMAGE_NAME="$1"      # e.g. ccop/grafana
IMAGE_VERSION="$2"   # e.g. 13.2.1
OUTPUT_BASE="$3"     # e.g. /opt/ansible/files/grafana
TS="$4"              # e.g. 20260916T134217Z

IMAGE_REF="${IMAGE_NAME}:${IMAGE_VERSION}"

SAFE_NAME="$(echo "${IMAGE_NAME}_${IMAGE_VERSION}" | sed -E 's/[^a-zA-Z0-9]+/_/g; s/^_//; s/_$//')"

# ---------------------------------------------------------------
# Quarter Auto-Detection
# ---------------------------------------------------------------
Q_OUT=$( /opt/ansible/files/common/scripts/determine_quarters.sh )
QUARTER=$(echo "$Q_OUT" | grep '^quarter=' | cut -d= -f2)

if [[ -z "${QUARTER}" || "${QUARTER}" == "unknown" ]]; then
    echo "ERROR: QUARTER could not be determined automatically."
    exit 2
fi

echo "Using quarter: ${QUARTER}"

# ---------------------------------------------------------------
# Output Directory
# ---------------------------------------------------------------
if [[ "${IMAGE_NAME}" == ccop/* ]]; then
    OUTPUT_DIR="${OUTPUT_BASE}/${QUARTER}/provenance/ccop"
elif [[ "${IMAGE_NAME}" == container-forge/* ]]; then
    OUTPUT_DIR="${OUTPUT_BASE}/${QUARTER}/provenance/container-forge"
else
    OUTPUT_DIR="${OUTPUT_BASE}/${QUARTER}/provenance/nucleus"
fi

mkdir -p "${OUTPUT_DIR}"

LOG="${OUTPUT_DIR}/scan_${SAFE_NAME}_${TS}.log"

echo "=== Universal Container Scan Pipeline ===" | tee "${LOG}"
echo "Image: ${IMAGE_REF}" | tee -a "${LOG}"
echo "Safe Name: ${SAFE_NAME}" | tee -a "${LOG}"
echo "Timestamp: ${TS}" | tee -a "${LOG}"
echo "Output Dir: ${OUTPUT_DIR}" | tee -a "${LOG}"
echo | tee -a "${LOG}"

# ---------------------------------------------------------------
# Step 1: SBOM + Vulnerability Scan
# ---------------------------------------------------------------
echo "[1/3] SBOM + Vulnerability Scan" | tee -a "${LOG}"

SBOM_SCRIPT="/opt/ansible/files/common/scripts/sbom_generate_and_scan.sh"

if ! "${SBOM_SCRIPT}" \
        --image "${IMAGE_REF}" \
        --output "${OUTPUT_DIR}" \
        --timestamp "${TS}" \
        --safe-name "${SAFE_NAME}" >> "${LOG}" 2>&1; then
    echo "ERROR: SBOM scan failed for ${IMAGE_REF}" | tee -a "${LOG}"
    exit 10
fi

echo "SBOM scan complete." | tee -a "${LOG}"
echo | tee -a "${LOG}"

# ---------------------------------------------------------------
# Step 2: Compensating Control Verification (distroless-safe)
# ---------------------------------------------------------------
echo "[2/3] Compensating Control Verification" | tee -a "${LOG}"

CID=$(docker create "${IMAGE_REF}")

TMP_ROOT="/opt/ansible/molecule/scans/tmp/${SAFE_NAME}_${TS}_rootfs"
mkdir -p "${TMP_ROOT}"

docker cp "${CID}:/usr" "${TMP_ROOT}/usr" || true
docker cp "${CID}:/bin" "${TMP_ROOT}/bin" || true
docker cp "${CID}:/usr/lib" "${TMP_ROOT}/usr/lib" || true

docker rm "${CID}" >/dev/null 2>&1 || true

VERIFIER="/opt/ansible/files/common/scripts/compensating_control_verifier.sh"

if ! "${VERIFIER}" "${TMP_ROOT}" >> "${LOG}" 2>&1; then
    echo "WARNING: Compensating Control Verification failed for ${IMAGE_REF}" | tee -a "${LOG}"
else
    echo "Compensating Control Verification complete." | tee -a "${LOG}"
fi

echo | tee -a "${LOG}"

# ---------------------------------------------------------------
# Step 3: OpenSCAP Scan (best-effort)
# ---------------------------------------------------------------
echo "[3/3] OpenSCAP Scan (best-effort)" | tee -a "${LOG}"

OPENSCAP_SCRIPT="/opt/ansible/files/common/scripts/openscap_container_scan.sh"
NAME="${SAFE_NAME}_${TS}"

if ! "${OPENSCAP_SCRIPT}" \
        "${IMAGE_REF}" \
        "${OUTPUT_DIR}" \
        "${NAME}" >> "${LOG}" 2>&1; then
    echo "WARNING: OpenSCAP scan failed for ${IMAGE_REF}, continuing build." | tee -a "${LOG}"
else
    echo "OpenSCAP scan complete." | tee -a "${LOG}"
fi

echo | tee -a "${LOG}"

echo "=== Universal Container Scan Pipeline Finished Successfully ===" | tee -a "${LOG}"
exit 0
