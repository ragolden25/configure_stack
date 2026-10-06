#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Pipeline Metadata
# ---------------------------------------------------------------------------

umask 022

IMAGE=""
OUTPUT_DIR=""
TS=""
SAFE_NAME=""
USE_LOCAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --image)      IMAGE="$2"; shift 2 ;;
        --output)     OUTPUT_DIR="$2"; shift 2 ;;
        --timestamp)  TS="$2"; shift 2 ;;
        --safe-name)  SAFE_NAME="$2"; shift 2 ;;
        --use-local-images) USE_LOCAL=1; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$IMAGE" || -z "$OUTPUT_DIR" ]]; then
    echo "Usage: sbom_generate_and_scan.sh --image <image> --output <dir>"
    exit 1
fi

[[ -z "$TS" ]] && TS=$(date -u +"%Y%m%dT%H%M%SZ")
[[ -z "$SAFE_NAME" ]] && SAFE_NAME="$(echo "$IMAGE" | sed 's|/|-|g' | sed 's|:|_|g')"

echo "==> Using image: $IMAGE"
echo "==> Output directory: $OUTPUT_DIR"
echo "==> Timestamp: $TS"
echo "==> Safe name: $SAFE_NAME"

mkdir -p "$OUTPUT_DIR"


# ---------------------------------------------------------------------------
# 2. Derived Filenames (SBOM + Vulnerability + Normalized)
# ---------------------------------------------------------------------------

SBOM_JSON="${OUTPUT_DIR}/${SAFE_NAME}.${TS}.sbom.json"
VULN_JSON="${OUTPUT_DIR}/${SAFE_NAME}.${TS}.vuln.json"
VULN_CSV="${OUTPUT_DIR}/${SAFE_NAME}.${TS}.vuln.csv"
NORMALIZED="${OUTPUT_DIR}/${SAFE_NAME}.${TS}.vuln.normalized.csv"


# ---------------------------------------------------------------------------
# 3. Template Paths + HTML Output Files
# ---------------------------------------------------------------------------

GRYPE_TEMPLATE="/opt/ansible/files/common/templates/grype.tpl"
SYFT_TEMPLATE="/opt/ansible/files/common/templates/syft.tpl"

VULN_HTML="${OUTPUT_DIR}/${SAFE_NAME}.${TS}.vuln.html"
SBOM_HTML="${OUTPUT_DIR}/${SAFE_NAME}.${TS}.sbom.html"


# ---------------------------------------------------------------------------
# 4. SBOM Generation (Syft)
# ---------------------------------------------------------------------------

echo "==> [SBOM] Generating SBOM with Syft"
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    anchore/syft:latest "$IMAGE" -o json > "$SBOM_JSON"

sync


# ---------------------------------------------------------------------------
# 5. Vulnerability Scan (Grype JSON)
# ---------------------------------------------------------------------------

echo "==> [VULN] Running Grype vulnerability scan (JSON)"
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    anchore/grype:latest "$IMAGE" -o json > "$VULN_JSON"

sync


# ---------------------------------------------------------------------------
# 6. CSV Conversion + Normalization
# ---------------------------------------------------------------------------

echo "==> [CSV] Converting Grype JSON → CSV (.matches[] schema)"
jq -r '
  .matches[]? |
  [
    .vulnerability.id,
    .vulnerability.severity,
    .artifact.name,
    .artifact.version,
    (.vulnerability.fix.state // "none"),
    (.vulnerability.fix.versions // [] | join(";"))
  ] | @csv
' "$VULN_JSON" > "$VULN_CSV"

echo "==> [CSV] Normalizing vuln CSV for IA"
 /opt/ansible/files/common/scripts/normalize_vuln_csv.sh "$VULN_CSV"


# ---------------------------------------------------------------------------
# 7. HTML Rendering (Grype Only)
# ---------------------------------------------------------------------------
echo "==> [HTML] Generating Grype HTML report"
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${GRYPE_TEMPLATE}:/tmp/grype.tpl:ro" \
    -v "${OUTPUT_DIR}:/output:ro" \
    anchore/grype:latest \
    -o template \
    --template /tmp/grype.tpl \
    "sbom:/output/$(basename "${SBOM_JSON}")" > "${VULN_HTML}"


#        -o template=/output/"${SAFE_NAME}.${TS}.vuln.html" \


# ---------------------------------------------------------------------------
# 8. Final Summary
# ---------------------------------------------------------------------------

echo "==> SBOM JSON:       $SBOM_JSON"
echo "==> Vuln JSON:       $VULN_JSON"
echo "==> Vuln CSV:        $VULN_CSV"
echo "==> Normalized CSV:  $NORMALIZED"
echo "==> Grype HTML:      $VULN_HTML"

echo "SBOM + vulnerability scan complete."
