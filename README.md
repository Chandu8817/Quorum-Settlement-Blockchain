# VittaGems Settlement Blockchain

Permissioned B2B settlement network built on Quorum (IBFT consensus).

## Quick Start

```bash
# Install dependencies
npm install

# Deploy the network (3 validators + 2 RPC + bootnode + monitoring)
sudo bash deploy-network.sh --reset

# Check status
npm run network:status

# Compile and deploy contracts
npm run compile
npm run deploy:local

# Run tests
npx hardhat run scripts/test-lifecycle.js --network quorum_local
npx hardhat run scripts/deploy/deploy-permissioning.js --network quorum_local
npx hardhat run scripts/test-permissioning.js --network quorum_local
bash scripts/test-validator-failover.sh
```

## Prerequisites

- Ubuntu 22.04 LTS
- Docker & Docker Compose
- Node.js 20+ (via nvm)
- Go 1.22+

Run `bash vittagems-env-setup.sh` to install everything.

## Network

| Node | Port | Role |
|------|------|------|
| Validator 1 | 8545 | Consensus + primary RPC |
| Validator 2 | 8547 | Consensus |
| Validator 3 | 8549 | Consensus |
| RPC 1 | 8551 | API endpoint |
| RPC 2 | 8553 | API failover |
| Grafana | 3000 | Monitoring (admin/vittagems) |
| Prometheus | 9090 | Metrics |

## Contracts

| Contract | Purpose |
|----------|---------|
| VittaGemsSettlement | Mint, transfer, burn, hold, freeze, reconcile |
| VittaGemsRBAC | Role-based access (Treasury, Compliance, Agent, Auditor, Partner) |
| `contracts/permissioning/quorum/*` | GoQuorum enhanced (v2) permissioning suite — **the enforcing layer** |
| VittaGemsNodePermissioning / …Account… | Legacy Besu-style contracts, retained for reference, **not enforced** (see below) |

## Permissioning

The chain enforces **GoQuorum enhanced (v2) permissioning**: unknown accounts
cannot transact, unapproved nodes cannot join. See
[`docs/ENHANCED_PERMISSIONING.md`](docs/ENHANCED_PERMISSIONING.md).

```bash
# rebuild the chain with permissioning active (DESTRUCTIVE: wipes chain data)
bash scripts/permissioning/rebuild-with-permissioning.sh

# prove enforcement
npx hardhat run scripts/permissioning/verify-permissioning.js --network quorum_local
```

The two `VittaGems*Permissioning.sol` contracts and
`scripts/deploy/deploy-permissioning.js` are kept for reference only — GoQuorum
never calls their Besu-style `transactionAllowed(...)` interface.

## Commands

| Command | What |
|---------|------|
| `sudo bash deploy-network.sh --reset` | Fresh network deployment |
| `npm run network:status` | Check node status |
| `npm run network:start` | Start network |
| `npm run network:stop` | Stop network |
| `npm run compile` | Compile contracts |
| `npm run deploy:local` | Deploy settlement contract |
| `npm test` | Run unit tests |

## Docs

Full technical documentation is in `docs/TECHNICAL_DOCS.md`.
