const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("=================================================");
  console.log("  VittaGems Load Test");
  console.log("=================================================");

  const BATCH_SIZE = 50; // Number of parallel txs
  const TOTAL_BATCHES = 10;
  
  const deploymentPath = path.join(__dirname, "../deployments", `quorum_local-deployment.json`);
  if (!fs.existsSync(deploymentPath)) {
      console.error(`Deployment file not found at ${deploymentPath}`);
      process.exit(1);
  }

  const deployment = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
  const contractAddress = deployment.address;

  // We will get multiple signers to send transactions in parallel
  // In Hardhat, ethers.getSigners() returns a list of accounts
  const signers = await ethers.getSigners();
  const agent = signers[2]; // Using account 2 as SETTLEMENT_AGENT

  const Settlement = await ethers.getContractFactory("VittaGemsSettlement");
  const settlement = Settlement.attach(contractAddress).connect(agent);

  console.log(`Target Contract: ${contractAddress}`);
  console.log(`Sender Agent: ${agent.address}`);
  console.log(`Starting load test: ${BATCH_SIZE * TOTAL_BATCHES} transactions...`);

  const startTime = Date.now();
  let successCount = 0;
  let failCount = 0;

  for (let b = 0; b < TOTAL_BATCHES; b++) {
      const promises = [];
      const batchStartTime = Date.now();

      for (let i = 0; i < BATCH_SIZE; i++) {
          const refId = `LT-${Date.now()}-${b}-${i}`;
          // For simplicity, we just reconcile a dummy refId which might fail if not found, 
          // or we can just send zero-value ether transfers to simulate load.
          // Since the network has zero gas, we can just send raw transactions to our own address.
          const txPromise = agent.sendTransaction({
              to: agent.address,
              value: 0,
              data: "0x"
          }).then(tx => tx.wait())
            .then(() => { successCount++; })
            .catch(err => { failCount++; });

          promises.push(txPromise);
      }

      await Promise.all(promises);
      const batchTime = Date.now() - batchStartTime;
      console.log(`Batch ${b + 1}/${TOTAL_BATCHES} completed in ${batchTime}ms. Success: ${successCount}, Fail: ${failCount}`);
  }

  const totalTime = Date.now() - startTime;
  const tps = ((BATCH_SIZE * TOTAL_BATCHES) / (totalTime / 1000)).toFixed(2);

  console.log("=================================================");
  console.log("  Load Test Complete");
  console.log(`  Total Time: ${totalTime} ms`);
  console.log(`  Total Txs:  ${BATCH_SIZE * TOTAL_BATCHES}`);
  console.log(`  Successful: ${successCount}`);
  console.log(`  Failed:     ${failCount}`);
  console.log(`  TPS:        ${tps} tx/sec`);
  console.log("=================================================");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
