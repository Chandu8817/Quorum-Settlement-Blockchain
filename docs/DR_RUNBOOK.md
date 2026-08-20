# Disaster Recovery Runbook: VittaGems Settlement Network

This runbook outlines the procedures for handling various failure scenarios in the VittaGems Settlement Network running on AWS (Single Node MVP setup).

## Scenario 1: Validator Node Crash (Docker Container Failure)

**Symptoms:**
- Grafana dashboard shows peer count dropped.
- `docker ps` shows one of the `vittagems-validatorX` containers as exited or restarting.

**Impact:**
- Because the network runs IBFT with 3 validators, a single validator crash is tolerated. Block production will continue without interruption.

**Recovery Steps:**
1. SSH into the AWS server.
2. View the logs for the failing container:
   ```bash
   docker logs --tail 100 vittagems-validator1
   ```
3. Restart the container:
   ```bash
   docker restart vittagems-validator1
   ```
4. Verify it reconnects and syncs:
   ```bash
   npm run network:status
   ```
   The block height for the restarted validator should quickly catch up to the others.

---

## Scenario 2: EC2 Instance Failure (Hardware / OS Crash)

**Symptoms:**
- The AWS server is unreachable via SSH.
- RPC endpoints timeout.
- CloudWatch metrics stop reporting.

**Impact:**
- Critical outage. All nodes are down. Settlement engine cannot process transactions.

**Recovery Steps:**
1. In the AWS Console, reboot the EC2 instance.
2. If the instance fails to reboot, attach the EBS volume to a new `t3.large` instance.
3. Once the server is online, SSH in and navigate to the project directory:
   ```bash
   cd ~/vittagems-blockchain
   ```
4. Restart the Docker network:
   ```bash
   npm run network:start
   ```
   (The `docker-compose.yml` is configured with `restart: unless-stopped`, so it may come up automatically on boot).
5. Verify block production has resumed from the last known block:
   ```bash
   npm run network:status
   ```

---

## Scenario 3: Corrupted Blockchain Data

**Symptoms:**
- Node logs show leveldb corruption errors or state mismatch.
- A node is stuck and cannot sync even after restart.

**Recovery Steps:**
1. Stop the corrupted node:
   ```bash
   docker stop vittagems-validator1
   ```
2. Delete its chain data, preserving the `nodekey`, `genesis.json`, `static-nodes.json`, and `permissioned-nodes.json`:
   ```bash
   cd ~/vittagems-blockchain/network/validator1/data
   rm -rf geth
   ```
3. Re-initialize the node with the genesis block:
   ```bash
   docker run --rm -v $(pwd):/data quorumengineering/quorum:latest geth --datadir /data init /data/genesis.json
   ```
4. Copy the permissioning files into the newly created `geth` directory:
   ```bash
   cp static-nodes.json permissioned-nodes.json geth/
   ```
5. Start the node:
   ```bash
   docker start vittagems-validator1
   ```
6. The node will sync the entire chain from block 0 from its peers. This may take some time depending on the chain height.

---

## Scenario 4: Accidental Network Reset (Data Loss)

**Symptoms:**
- Someone accidentally ran `deploy-network.sh --reset`, wiping all chain data.

**Impact:**
- Catastrophic data loss. The chain starts from block 0. Contracts and balances are gone.

**Recovery Steps (Requires Backups):**
*Note: A cron job should be configured to back up the `/data/geth` directories periodically to S3.*
1. Stop the network completely:
   ```bash
   docker stop $(docker ps -q)
   ```
2. Download the latest backup from S3:
   ```bash
   aws s3 cp s3://vittagems-backups/latest-backup.tar.gz .
   tar -xzf latest-backup.tar.gz
   ```
3. Overwrite the `network/*/data/geth` directories with the extracted backup.
4. Restart the network:
   ```bash
   npm run network:start
   ```
5. The network will resume from the block height at the time of the backup. Any transactions processed after the backup but before the crash are lost and must be reconciled manually via off-chain logs.
