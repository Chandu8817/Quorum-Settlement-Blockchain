/**
 * VittaGems — Suspend / reactivate / blacklist a permissioned account
 * =================================================================
 * Runs as the deployer/guardian (an org admin of the network admin org).
 *
 * Usage:
 *   ACCOUNT=0xabc... npx hardhat run scripts/permissioning/revoke-account.js --network quorum_local
 *
 *   ACCOUNT   required — address to act on
 *   ACTION    optional — 1 suspend (default), 2 reactivate, 3 blacklist
 *
 * Blacklisting (3) is not reversible through this script — recovery needs the
 * multi-step recoverBlackListedAccount / approveBlackListedAccountRecovery flow.
 */
const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const ACTIONS = { 1: "suspend", 2: "reactivate", 3: "blacklist" };

const IFACE_ABI = [
  "function updateAccountStatus(string _orgId, address _account, uint256 _action) external",
];
const IMPL_ABI = [
  "function transactionAllowed(address,address,uint256,uint256,uint256,bytes) view returns (bool)",
];

async function main() {
  const account = process.env.ACCOUNT;
  const action = Number(process.env.ACTION ?? 1);

  if (!account || !hre.ethers.isAddress(account)) {
    console.error("  ✗ Set ACCOUNT=0x... to a valid address");
    process.exit(1);
  }
  if (!ACTIONS[action]) {
    console.error("  ✗ ACTION must be 1 (suspend), 2 (reactivate) or 3 (blacklist)");
    process.exit(1);
  }

  const cfg = JSON.parse(
    fs.readFileSync(path.join(ROOT, "config", "permission-config.json"), "utf8")
  );
  const [signer] = await hre.ethers.getSigners();
  const iface = new hre.ethers.Contract(cfg.interfaceAddress, IFACE_ABI, signer);
  const impl = new hre.ethers.Contract(cfg.implAddress, IMPL_ABI, hre.ethers.provider);

  console.log("============================================================");
  console.log(`  ${ACTIONS[action]} account`);
  console.log("============================================================");
  console.log(`  org:     ${cfg.nwAdminOrg}`);
  console.log(`  account: ${account}`);
  console.log(`  sender:  ${signer.address}`);
  console.log("");

  const before = await impl.transactionAllowed(
    account, hre.ethers.ZeroAddress, 0n, 0n, 0n, "0x"
  );
  console.log(`  transactionAllowed before: ${before}`);

  const tx = await iface.updateAccountStatus(cfg.nwAdminOrg, account, action);
  const rcpt = await tx.wait();
  console.log(`  ✓ ${ACTIONS[action]} applied in block ${rcpt.blockNumber}`);

  const after = await impl.transactionAllowed(
    account, hre.ethers.ZeroAddress, 0n, 0n, 0n, "0x"
  );
  console.log(`  transactionAllowed after:  ${after}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
