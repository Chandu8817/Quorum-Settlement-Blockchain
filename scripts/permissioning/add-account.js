/**
 * VittaGems — Permission an additional account
 * ===========================================
 * Grants an account the right to transact on the network. Use this for service
 * accounts (backend API, settlement agent, integration clients) that were not
 * present when the network was bootstrapped.
 *
 * Runs as the deployer/guardian, which is an org admin of the network admin org.
 * (The quorumPermission_* RPC methods need the sending key to live in a node
 * keystore; our nodes only carry nodekeys, so we call the contracts directly.)
 *
 * Usage:
 *   ACCOUNT=0xabc... npx hardhat run scripts/permissioning/add-account.js --network quorum_local
 *
 *   ACCOUNT   required — address to permission
 *   ROLE      optional — role id (default SETTLEMENT_SVC)
 *   ACCESS    optional — 0 read-only, 1 transact, 2 transact+deploy, 3 full
 *                        (default 2)
 *
 * Prefer a scoped role over network admin: a service account should not be able
 * to vote on org changes or manage other accounts.
 */
const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");

const IFACE_ABI = [
  "function addNewRole(string _roleId, string _orgId, uint256 _access, bool _voter, bool _admin) external",
  "function assignAccountRole(address _account, string _orgId, string _roleId) external",
];
const IMPL_ABI = [
  "function transactionAllowed(address,address,uint256,uint256,uint256,bytes) view returns (bool)",
];

async function main() {
  const account = process.env.ACCOUNT;
  const roleId = process.env.ROLE || "SETTLEMENT_SVC";
  const access = Number(process.env.ACCESS ?? 2);

  if (!account || !hre.ethers.isAddress(account)) {
    console.error("  ✗ Set ACCOUNT=0x... to a valid address");
    process.exit(1);
  }

  const cfg = JSON.parse(
    fs.readFileSync(path.join(ROOT, "config", "permission-config.json"), "utf8")
  );
  const [signer] = await hre.ethers.getSigners();
  const iface = new hre.ethers.Contract(cfg.interfaceAddress, IFACE_ABI, signer);
  const impl = new hre.ethers.Contract(cfg.implAddress, IMPL_ABI, hre.ethers.provider);

  console.log("============================================================");
  console.log("  Permission account");
  console.log("============================================================");
  console.log(`  org:     ${cfg.nwAdminOrg}`);
  console.log(`  account: ${account}`);
  console.log(`  role:    ${roleId} (access ${access})`);
  console.log(`  sender:  ${signer.address}`);
  console.log("");

  const before = await impl.transactionAllowed(
    account, hre.ethers.ZeroAddress, 0n, 0n, 0n, "0x"
  );
  console.log(`  transactionAllowed before: ${before}`);

  // Create the role if it does not exist yet. Re-running is harmless: a
  // duplicate addNewRole reverts and we carry on to the assignment.
  try {
    const tx = await iface.addNewRole(roleId, cfg.nwAdminOrg, access, false, false);
    await tx.wait();
    console.log(`  ✓ role ${roleId} created`);
  } catch (e) {
    console.log(`  · role ${roleId} not created (likely already exists)`);
  }

  const tx2 = await iface.assignAccountRole(account, cfg.nwAdminOrg, roleId);
  const rcpt = await tx2.wait();
  console.log(`  ✓ assigned in block ${rcpt.blockNumber}`);

  const after = await impl.transactionAllowed(
    account, hre.ethers.ZeroAddress, 0n, 0n, 0n, "0x"
  );
  console.log(`  transactionAllowed after:  ${after}`);
  console.log("");
  console.log(after ? "  RESULT: account can now transact ✓" : "  RESULT: still blocked ✗");
  process.exitCode = after ? 0 : 1;
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
