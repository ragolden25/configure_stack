/opt/ansible/build/grafana_stack/grafana/scripts
# detect_grafana_version.sh
#!/usr/bin/env bash
set -euo pipefail

STAGED_ROOT="/opt/ansible/staged/grafana"

# ------------------------------------------------------------
# Find all semver directories
# ------------------------------------------------------------
mapfile -t VERSIONS < <(
    ls -1 "${STAGED_ROOT}" \
      | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' \
      | sort -V
)

if [[ ${#VERSIONS[@]} -eq 0 ]]; then
    echo "ERROR: No Grafana version directories found in ${STAGED_ROOT}" >&2
    exit 1
fi

VALID_VERSIONS=()

# ------------------------------------------------------------
# Validate each version directory
# ------------------------------------------------------------
for VERSION in "${VERSIONS[@]}"; do
    BASE_DIR="${STAGED_ROOT}/${VERSION}"
    INVENTORY="${BASE_DIR}/inventory.env"
    STAGED_DIR="${BASE_DIR}/staged"

    # Must have inventory.env
    if [[ ! -f "${INVENTORY}" ]]; then
        continue
    fi

    # Must have required staged artifacts
    if [[ ! -f "${STAGED_DIR}/bin/grafana" ]]; then
        continue
    fi

    if [[ ! -d "${STAGED_DIR}/public" ]]; then
        continue
    fi

    if [[ ! -d "${STAGED_DIR}/conf" ]]; then
        continue
    fi

    VALID_VERSIONS+=("${VERSION}")
done

if [[ ${#VALID_VERSIONS[@]} -eq 0 ]]; then
    echo "ERROR: No fully staged Grafana versions found in ${STAGED_ROOT}" >&2
    exit 2
fi

# ------------------------------------------------------------
# Output the latest valid version
# ------------------------------------------------------------
LATEST="${VALID_VERSIONS[-1]}"
echo "${LATEST}"
