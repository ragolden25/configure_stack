#!/bin/bash
set -euo pipefail

echo "Select image to build:"
echo "1) base"
echo "2) go"
echo "3) node20"
echo "4) node22"
echo "0) exit"

read -r choice

case "$choice" in
  1) /root/bin/mmdebstrap-build-base.sh ;;
  2) /root/bin/mmdebstrap-build-go.sh ;;
  3) /root/bin/mmdebstrap-build-node20.sh ;;
  4) /root/bin/mmdebstrap-build-node22.sh ;;
  0) exit 0 ;;
  *) echo "Invalid selection" ;;
esac
