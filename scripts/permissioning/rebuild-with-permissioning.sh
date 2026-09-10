#!/usr/bin/env bash
#
# VittaGems — Rebuild the chain WITH GoQuorum enhanced (v2) permissioning
# ====================================================================
# DESTRUCTIVE: wipes chain data (blocks + previously-deployed contracts) and
# re-inits every node from the updated genesis, then activates smart-contract
# based account + node permissioning.
#
# It deliberately does NOT call deploy-network.sh: that regenerates every node
# key (new validator/deployer addresses). This keeps all existing keys so the
# deployer account, hardhat.config.js and config/operational-accounts.json all
# stay valid.
#
# Phases:
#   0  pre-flight, confirm
#   1  stop network, wipe chaindata, clear stale permission-config.json
#   2  geth init every node against config/genesis.json (qip714Block=0, maxCodeSize=35)
#   3  start network            -> only basic node permissioning; accounts open
#   4  bootstrap-permissioning.js -> deploy suite + write permission-config.json
#   5  restart network          -> PermissionModel=v2; geth runs one-time bootup
#   6  poll on-chain boot status until complete
#   7  verify-permissioning.js  -> proves a stranger account is now rejected
#   8  redeploy VittaGemsSettlement (deployer is a network admin)
#
# Usage: bash scripts/permissioning/rebuild-with-permissioning.sh [--yes]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/_wsl-env.sh"

mkdir -p "$PROJECT_DIR/deployments"
exec > >(tee "$PROJECT_DIR/deployments/rebuild-$(date +%Y%m%d-%H%M%S).log") 2>&1

RPC="http://localhost:8545"
COMPOSE=(docker compose -f "$PROJECT_DIR/docker/docker-compose.yml")
QUORUM_IMAGE="quorumengineering/quorum:latest"
ASSUME_YES=0
[ "${1:-}" = "--yes" ] && ASSUME_YES=1

say() { printf '\n\033[1;36m━━━ %s\033[0m\n' "$*"; }
ok()  { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
die() { printf '  \033[0;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

rpc() {
  curl -s -X POST "$RPC" -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":${2:-[]},\"id\":1}"
}
blocknum() { rpc eth_blockNumber | sed 's/.*"result":"\([^"]*\)".*/\1/'; }

wait_for_rpc() {
  for _ in $(seq 1 "${1:-60}"); do
    rpc eth_blockNumber | grep -q '"result"' && return 0
    sleep 2
  done
  return 1
}
wait_for_blocks() {
  local a b; a=$(blocknum)
  for _ in $(seq 1 40); do
    sleep 3; b=$(blocknum)
    [ "$a" != "$b" ] && return 0
  done
  return 1
}

NODES=()
for d in "$PROJECT_DIR"/network/*/; do
  n=$(basename "$d")
  [ -f "$PROJECT_DIR/network/$n/data/nodekey" ] && NODES+=("$n")
done

# ── 0. pre-flight ──────────────────────────────────────────────────────────
say "0 · Pre-flight"
docker info >/dev/null 2>&1 || die "docker daemon not reachable"
command -v jq >/dev/null 2>&1 || die "jq required (apt install jq)"
[ "${#NODES[@]}" -ge 4 ] || die "expected >=4 node dirs under network/, found ${#NODES[@]}"
grep -q '"qip714Block": 0'  "$PROJECT_DIR/config/genesis.json" || die "config/genesis.json missing qip714Block:0"
grep -q 'maxCodeSizeConfig' "$PROJECT_DIR/config/genesis.json" || die "config/genesis.json missing maxCodeSizeConfig"
grep -q -- '--permissioned' "$PROJECT_DIR/docker/docker-compose.yml" || die "docker-compose.yml missing --permissioned"
[ -f "$PROJECT_DIR/artifacts/contracts/permissioning/quorum/PermissionsImplementation.sol/PermissionsImplementation.json" ] \
  || die "permissioning suite not compiled — run: npx hardhat compile"
ok "nodes: ${NODES[*]}"

if [ "$ASSUME_YES" -ne 1 ]; then
  printf '  This DELETES all current chain data (blocks + deployed contracts) and rebuilds.\n'
  read -r -p "  Type 'rebuild' to proceed: " ans
  [ "$ans" = "rebuild" ] || die "aborted"
fi

# ── 1. stop + wipe ────────────────────────────────────────────────────────
say "1 · Stop network, wipe chaindata"
( cd "$PROJECT_DIR/docker" && "${COMPOSE[@]}" down ) || true
rm -f "$PROJECT_DIR/config/permission-config.json"
for n in "${NODES[@]}"; do
  data="$PROJECT_DIR/network/$n/data"
  # geth in the compose services runs as root, so chaindata files are root-owned
  # and cannot be removed by the WSL user. Wipe from inside a throwaway container.
  docker run --rm --entrypoint="" -v "${data}:/data" "$QUORUM_IMAGE" \
    sh -c 'rm -rf /data/geth /data/quorum-raft-state /data/permission-config.json /data/geth.ipc' \
    || die "$n chaindata wipe failed"
  rm -f "$PROJECT_DIR/network/$n/data/permission-config.json" 2>/dev/null || true
  rm -f "$PROJECT_DIR/network/$n/logs/"* 2>/dev/null || true
  ok "$n wiped"
done
ok "chaindata + stale permission-config.json removed"

# ── 2. re-init from updated genesis ──────────────────────────────────────
say "2 · geth init against updated genesis"
for n in "${NODES[@]}"; do
  data="$PROJECT_DIR/network/$n/data"
  cp "$PROJECT_DIR/config/genesis.json" "$data/genesis.json"
  [ -f "$PROJECT_DIR/config/static-nodes.json" ] && cp "$PROJECT_DIR/config/static-nodes.json" "$data/"
  [ -f "$PROJECT_DIR/config/permissioned-nodes.json" ] && cp "$PROJECT_DIR/config/permissioned-nodes.json" "$data/"
  # init as root to match how the compose services run (keeps chaindata
  # ownership consistent; wipe is always container-based anyway).
  docker run --rm --entrypoint="" \
    -v "${data}:/data" "$QUORUM_IMAGE" \
    geth --datadir /data init /data/genesis.json >/dev/null 2>&1 \
    && ok "$n initialised" || die "$n geth init failed"
  # geth/ is root-owned after init; mirror the node lists into it via container
  docker run --rm --entrypoint="" -v "${data}:/data" "$QUORUM_IMAGE" sh -c '
    [ -d /data/geth ] || exit 0
    [ -f /data/static-nodes.json ] && cp /data/static-nodes.json /data/geth/ || true
    [ -f /data/permissioned-nodes.json ] && cp /data/permissioned-nodes.json /data/geth/ || true
  ' || true
done

# ── 3. start (accounts still open — no permission-config.json yet) ───────
say "3 · Start network"
( cd "$PROJECT_DIR/docker" && "${COMPOSE[@]}" up -d )
wait_for_rpc 90 || die "validator1 RPC never came up"
wait_for_blocks || { ( cd "$PROJECT_DIR/docker" && "${COMPOSE[@]}" logs --tail=30 validator1 ); die "chain not producing blocks"; }
ok "network up at block $(blocknum)"

# ── 4. deploy permissioning suite ──────────────────────────────────────
say "4 · bootstrap-permissioning.js"
( cd "$PROJECT_DIR" && npx hardhat run scripts/permissioning/bootstrap-permissioning.js --network quorum_local )
[ -f "$PROJECT_DIR/config/permission-config.json" ] || die "permission-config.json not written"
for n in "${NODES[@]}"; do
  [ -f "$PROJECT_DIR/network/$n/data/permission-config.json" ] || die "permission-config.json missing for $n"
done
ok "suite deployed; permission-config.json distributed"

# ── 5. restart -> activate v2 ─────────────────────────────────────────
say "5 · Restart network (activate v2 permissioning)"
( cd "$PROJECT_DIR/docker" && "${COMPOSE[@]}" down && "${COMPOSE[@]}" up -d )
wait_for_rpc 90 || die "validator1 RPC did not return after restart"

# ── 6. wait for on-chain network boot ────────────────────────────────
say "6 · Wait for enhanced-permissioning network boot"
IFACE=$(jq -r '.interfaceAddress' "$PROJECT_DIR/config/permission-config.json")
booted=0
for i in $(seq 1 72); do
  res=$(rpc eth_call "[{\"to\":\"$IFACE\",\"data\":\"0x4cbfa82e\"},\"latest\"]" | sed 's/.*"result":"\([^"]*\)".*/\1/')
  case "$res" in *[1-9a-f]) booted=1; ok "network boot complete (~$((i*5))s)"; break;; esac
  sleep 5
done
if [ "$booted" -ne 1 ]; then
  ( cd "$PROJECT_DIR/docker" && "${COMPOSE[@]}" logs --tail=60 validator1 | grep -i "permission\|boot" || true )
  die "network did not boot — see logs above"
fi

# ── 7. prove enforcement ────────────────────────────────────────────
say "7 · verify-permissioning.js"
( cd "$PROJECT_DIR" && npx hardhat run scripts/permissioning/verify-permissioning.js --network quorum_local )

# ── 8. redeploy settlement contract ────────────────────────────────
say "8 · Redeploy VittaGemsSettlement"
( cd "$PROJECT_DIR" && npx hardhat run scripts/deploy/deploy-settlement.js --network quorum_local )

say "DONE — enhanced (v2) permissioning active"
printf '  config/permission-config.json .............. policy + contract addresses\n'
printf '  deployments/permissioning-v2-deployment.json .. suite deployment record\n'
printf '  Manage orgs/roles/accounts via the quorumPermission_* JSON-RPC API.\n'
