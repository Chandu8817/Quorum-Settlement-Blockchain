#!/usr/bin/env bash
# Lists every permission denial across all nodes, with the RPC client address.
# Useful for spotting a service whose account has not been permissioned.
set -u
for c in validator1 validator2 validator3 rpc1 rpc2 bootnode; do
  docker logs "vittagems-$c" 2>&1 \
    | grep "does not have permission" \
    | sed "s/^/[$c] /"
done
