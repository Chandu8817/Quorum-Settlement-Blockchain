# VittaGems API Integration Guide

This guide provides instructions for the Phase 2 DApp and Settlement Engine teams to integrate with the VittaGems Quorum Network running on AWS.

## Connection Details

- **RPC Endpoint:** `http://<AWS_ELASTIC_IP>:8545` or `http://<AWS_ELASTIC_IP>:8551`
- **Chain ID:** `7001`
- **Network Name:** `vittagems-aws`

## Integrating via Ethers.js (Node.js/Backend)

### 1. Provider Setup

```javascript
const { ethers } = require("ethers");

// Connect to the primary AWS RPC Node
const rpcUrl = "http://<AWS_ELASTIC_IP>:8545";
const provider = new ethers.JsonRpcProvider(rpcUrl);

// Optional: Fallback Provider for high availability (RPC 2)
// const fallbackProvider = new ethers.FallbackProvider([
//   { provider: new ethers.JsonRpcProvider(rpcUrl), priority: 1 },
//   { provider: new ethers.JsonRpcProvider("http://<AWS_ELASTIC_IP>:8551"), priority: 2 }
// ]);
```

### 2. Wallet & Signer Setup

To submit transactions, you must have an authorized account configured in the `VittaGemsAccountPermissioning` contract.

```javascript
// Load private key securely from AWS Secrets Manager or environment variables
const privateKey = process.env.SETTLEMENT_AGENT_PRIVATE_KEY;
const wallet = new ethers.Wallet(privateKey, provider);
```

### 3. Contract Interaction (Zero-Gas Transactions)

Since VittaGems is a zero-gas permissioned network, you must override `gasPrice` and optionally `gasLimit` when sending transactions, as Ethers.js might try to query fee data which Quorum does not require in the same way.

```javascript
const contractAddress = "0xYourDeployedSettlementContractAddress";
const abi = [
    "function mintWithTreasuryApproval(uint256 amount, address partner, string refId, string corridor) external",
    "function transfer(string refId, address to, uint256 amount) external"
];

const settlementContract = new ethers.Contract(contractAddress, abi, wallet);

// Example: Transfer Value
async function executeTransfer(refId, destinationPartner, amount) {
    try {
        const tx = await settlementContract.transfer(refId, destinationPartner, amount, {
            gasPrice: 0, // CRITICAL: Zero gas network
            gasLimit: 3000000 // Safe upper bound
        });
        
        console.log(`Transaction submitted. Hash: ${tx.hash}`);
        const receipt = await tx.wait();
        console.log(`Transaction confirmed in block: ${receipt.blockNumber}`);
        return receipt;
    } catch (error) {
        console.error("Transfer failed:", error.message);
        throw error;
    }
}
```

## Monitoring Contract Events

The Settlement Engine should listen for on-chain events to update the off-chain database.

```javascript
// Listen for TransferSettled events
settlementContract.on("TransferSettled", (refId, from, to, amount, event) => {
    console.log(`Transfer Confirmed!`);
    console.log(`Ref ID: ${refId}`);
    console.log(`Amount: ${ethers.formatEther(amount)} VG`);
    
    // TODO: Update off-chain database via webhook or internal API
});
```

## Rate Limiting & Failover

- The AWS t3.large instance can handle ~100-200 TPS comfortably.
- If you receive `429 Too Many Requests` or connection timeouts, implement a retry mechanism with exponential backoff, or switch to the secondary RPC node on port `8551`.
