#!/bin/bash

echo "============================================================"
echo "  VittaGems Network — Full Reset"
echo "============================================================"
echo ""
read -p "  This will DELETE all chain data. Continue? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "  Cancelled."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "  Stopping containers..."
cd "${PROJECT_DIR}/docker" && docker compose down -v 2>/dev/null

echo "  Removing chain data..."
for data_dir in "${PROJECT_DIR}"/network/*/data; do
  rm -rf "${data_dir}/geth"
  rm -rf "${data_dir}/quorum-raft-state"
  rm -rf "${data_dir}/../logs/"*
  node_name=$(basename "$(dirname "$data_dir")")
  echo "    Cleaned: ${node_name}"
done

echo ""
echo "  ✓ Network reset complete."
echo "  Run 'npm run network:start' to reinitialize."
echo "============================================================"
