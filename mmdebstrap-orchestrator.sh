#!/bin/bash
set -euo pipefail

# mmdebstrap-orchestrator.sh

# Modular image builds

LOG="/root/bin/daily-build.log"
IMAGES="${IMAGES:-base go node20 node22 postgres18}"

echo "=== $(date -Iseconds) : Starting daily build ===" >> "$LOG"

for img in $IMAGES; do
    echo "--- $(date -Iseconds) : Building $img ---" >> "$LOG"

    # Run the build script WITHOUT strict mode
    if /root/bin/mmdebstrap-build-"$img".sh >> "$LOG" 2>&1; then
        echo "--- $(date -Iseconds) : $img build succeeded ---" >> "$LOG"
    else
        echo "--- $(date -Iseconds) : $img build FAILED ---" >> "$LOG"
        # Continue to next image — blast-radius protection
    fi
done

echo "=== $(date -Iseconds) : Daily build complete ===" >> "$LOG"
