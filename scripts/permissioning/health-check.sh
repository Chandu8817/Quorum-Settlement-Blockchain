#!/usr/bin/env bash
set -u
echo "=== BAD BLOCK / permission errors per node ==="
for c in validator1 validator2 validator3 rpc1 rpc2 bootnode; do
  bad=$(docker logs "vittagems-$c" 2>&1 | grep -c "BAD BLOCK")
  perm=$(docker logs "vittagems-$c" 2>&1 | grep -c "does not have permission")
  ready=$(docker logs "vittagems-$c" 2>&1 | grep -c "permission service: is now ready")
  model=$(docker logs "vittagems-$c" 2>&1 | grep -o "using v[12] permissions model" | tail -1)
  printf '%-11s badblocks=%-3s permDenied=%-3s ready=%-3s %s\n' "$c" "$bad" "$perm" "$ready" "$model"
done
