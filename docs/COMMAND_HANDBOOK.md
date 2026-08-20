# VittaGems Command Handbook & Execution Order

This handbook serves as a cheat sheet for all commands needed to operate the VittaGems Quorum network. It is structured chronologically for a fresh deployment, followed by a reference guide for all `npm`, `npx`, and `docker` commands.

---

## 1. The Correct Order of Execution (Fresh Deployment)

Whether you are deploying locally or to AWS, follow this exact sequence to ensure the network comes online and contracts are provisioned correctly.

### Step 1: Environment Setup
If you are on a fresh machine (Ubuntu), you must install Docker, Docker Compose, Node.js, and Go.
```bash
bash vittagems-env-setup.sh
```
*(Skip this if deploying to AWS using `deploy-to-aws.sh`, as it runs this automatically).*

### Step 2: Install Node Dependencies
Installs Hardhat and Ethers.js.
```bash
npm install
```

### Step 3: Deploy the Blockchain Network
This generates keys, writes genesis blocks, creates the Docker Compose file, and starts the nodes.
```bash
# Local deployment:
sudo bash deploy-network.sh --reset

# AWS remote deployment (from your local machine):
bash scripts/deploy-to-aws.sh <elastic-ip> ~/.ssh/your-key.pem ubuntu
```

### Step 4: Verify Network Status
Wait ~30 seconds, then check that all nodes are online and block numbers match.
```bash
npm run network:status
```

### Step 5: Compile Smart Contracts
Compile the Solidity code into ABI and bytecode artifacts.
```bash
npm run compile
```

### Step 6: Deploy Core Settlement Contract
Deploys `VittaGemsSettlement.sol` to the network.
```bash
npm run deploy:local
```

### Step 7: Deploy Permissioning Contracts
Registers the running nodes and admin accounts on-chain.
```bash
npx hardhat run scripts/deploy/deploy-permissioning.js --network quorum_local
```

### Step 8: Run Integration Tests
Verify everything is working end-to-end.
```bash
# Test the settlement lifecycle
npx hardhat run scripts/test-lifecycle.js --network quorum_local

# Test node and account permissioning
npx hardhat run scripts/test-permissioning.js --network quorum_local
```

---

## 2. NPM Scripts Reference

These are shortcuts defined in `package.json` for managing the network. Run them from the project root.

| Command | Description |
|---|---|
| `npm run network:start` | Starts the existing Docker network (`docker compose up -d`). Does not overwrite data. |
| `npm run network:stop` | Stops the Docker network gracefully (`docker compose down`). |
| `npm run network:status` | Checks block height and peer count for all validators and RPC nodes. |
| `npm run network:logs` | Streams live logs from all Docker containers. |
| `npm run compile` | Compiles Solidity contracts using Hardhat. |
| `npm run deploy:local` | Deploys the settlement contract using Validator 1's RPC. |
| `npm test` | Runs the Hardhat unit tests in the `test/` folder locally (fast, doesn't need Quorum). |

---

## 3. Hardhat Commands (npx)

Use `npx hardhat` to interact directly with the running Quorum network.

| Command | Description |
|---|---|
| `npx hardhat console --network quorum_local` | Opens an interactive JS console connected to the blockchain. |
| `npx hardhat run <script> --network quorum_local` | Executes a specific JS script against the blockchain. |
| `npx hardhat clean` | Clears the `artifacts/` and `cache/` directories. Useful if contract compilation gets stuck. |

---

## 4. Docker & Shell Commands

If you need to manually intervene with the nodes, use these Docker commands.

| Command | Description |
|---|---|
| `docker ps` | List all running containers. You should see 3 validators, 2 RPCs, bootnode, grafana, prometheus, and explorer. |
| `docker restart vittagems-validator1` | Restarts a specific node. Useful if a node gets stuck syncing. |
| `docker logs vittagems-rpc1 --tail 100 -f` | Tails the last 100 logs of a specific node and follows new output. |
| `docker exec -it vittagems-validator1 /bin/sh` | Drops you into a shell inside a running container. |

### Bash Scripts Reference

| Script | Purpose |
|---|---|
| `deploy-network.sh` | The core network orchestrator. Run with `--help` to see advanced options (like changing port mappings or block periods). |
| `scripts/deploy-to-aws.sh` | Rsyncs code and orchestrates a remote deployment to an EC2 instance via SSH. |
| `scripts/test-validator-failover.sh` | Tests IBFT resilience by intentionally stopping and starting Docker containers during consensus. |

---

## 5. UI Dashboards

Once the network is running, you can access these tools in your browser:

- **Grafana Metrics:** `http://localhost:3000` (or `http://<aws-ip>:3000`). Default login: `admin` / `vittagems`.
- **Prometheus:** `http://localhost:9090` (Raw metric data).
- **Ethereum Lite Explorer:** `http://localhost:8080`. (Click the gear icon to change the RPC URL to `http://<aws-ip>:8545` if accessing remotely).
