#!/usr/bin/env bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
IFACE=$(jq -r .interfaceAddress config/permission-config.json)
echo "interface: $IFACE"
RES=$(curl -s -X POST http://localhost:8545 -H 'Content-Type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$IFACE\",\"data\":\"0x4cbfa82e\"},\"latest\"],\"id\":1}")
echo "getNetworkBootStatus raw: $RES"
echo "block: $(curl -s -X POST http://localhost:8545 -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}')"
echo "--- recent permission logs ---"
docker logs vittagems-validator1 2>&1 | grep -iE "permission|boot|admin org|failed|error.*perm" | tail -15
