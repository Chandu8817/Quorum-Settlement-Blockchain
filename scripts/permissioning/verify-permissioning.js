/**
 * VittaGems — Verify GoQuorum Enhanced (v2) Permissioning is ENFORCED
 * =================================================================
 * Proves, empirically, that:
 *   1. the network reports v2 boot complete
 *   2. a permissioned account (deployer / network admin) CAN transact
 *   3. a brand-new, unknown account CANNOT transact (chain rejects it)
 *
 * Run: npx hardhat run scripts/permissioning/verify-permissioning.js --network quorum_local
 * Exit code 0 only if all three hold.
 */
const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");

const UPGRADABLE_ABI = [
  "function getPermInterface() view returns (address)",
  "function getPermImpl() view returns (address)",
  "function getGuardian() view returns (address)",
];
const IFACE_ABI = ["function getNetworkBootStatus() view returns (bool)"];
const IMPL_ABI = [
  "function isNetworkAdmin(address) view returns (bool)",
  "function transactionAllowed(address,address,uint256,uint256,uint256,bytes) view returns (bool)",
];

function permissionErr(e) {
  const s = JSON.stringify(e && (e.info || e.error || e.message || e)).toLowerCase();
  return (
    s.includes("not authorized") ||
    s.includes("not permitted") ||
    s.includes("permission") ||
    s.includes("read only account") ||
    s.includes("account is not authorized to send transactions")
  );
}

async function main() {
  const cfgPath = path.join(ROOT, "config", "permission-config.json");
  if (!fs.existsSync(cfgPath)) throw new Error("config/permission-config.json not found — run bootstrap first");
  const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));

  const provider = hre.ethers.provider;
  const [deployer] = await hre.ethers.getSigners();

  console.log("============================================================");
  console.log("  VittaGems — Enhanced Permissioning Enforcement Check");
  console.log("============================================================");
  console.log(`  permissionModel:  ${cfg.permissionModel}`);
  console.log(`  interfaceAddress: ${cfg.interfaceAddress}`);
  console.log(`  deployer:         ${deployer.address}`);
  console.log("");

  const results = {};

  // ---- 1. boot status ------------------------------------------------------
  const upgr = new hre.ethers.Contract(cfg.upgradableAddress, UPGRADABLE_ABI, provider);
  const ifaceAddr = await upgr.getPermInterface();
  const implAddr = await upgr.getPermImpl();
  const iface = new hre.ethers.Contract(ifaceAddr, IFACE_ABI, provider);
  const impl = new hre.ethers.Contract(implAddr, IMPL_ABI, provider);

  const booted = await iface.getNetworkBootStatus();
  results.bootComplete = booted === true;
  console.log(`  [1] network boot status ......... ${booted}  ${results.bootComplete ? "✓" : "✗"}`);
  console.log(`      guardian ................... ${await upgr.getGuardian()}`);

  // ---- 2. permissioned account can transact ------------------------------
  let adminFlag = null;
  try {
    adminFlag = await impl.isNetworkAdmin(deployer.address);
  } catch (_) {}
  let deployerCanTx = false;
  try {
    const tx = await deployer.sendTransaction({ to: deployer.address, value: 0 });
    await tx.wait();
    deployerCanTx = true;
  } catch (e) {
    console.log(`      deployer tx error: ${e.shortMessage || e.message}`);
  }
  results.adminCanTransact = deployerCanTx;
  console.log(`  [2] deployer isNetworkAdmin ..... ${adminFlag}`);
  console.log(`      deployer self-tx accepted .. ${deployerCanTx}  ${deployerCanTx ? "✓" : "✗"}`);

  // ---- 3. unknown account is rejected -----------------------------------
  const stranger = hre.ethers.Wallet.createRandom().connect(provider);
  console.log(`  [3] stranger (never registered): ${stranger.address}`);

  let strangerAllowedByContract = null;
  try {
    strangerAllowedByContract = await impl.transactionAllowed(
      stranger.address,
      "0x0000000000000000000000000000000000000000",
      0n,
      0n,
      0n,
      "0x"
    );
  } catch (_) {}
  console.log(`      transactionAllowed(stranger) = ${strangerAllowedByContract}`);

  let strangerRejected = false;
  let strangerOutcome;
  try {
    const tx = await stranger.sendTransaction({ to: stranger.address, value: 0, gasPrice: 0, gasLimit: 21000 });
    await tx.wait();
    strangerOutcome = `ACCEPTED in block ${tx.blockNumber ?? "?"} — NOT ENFORCED`;
  } catch (e) {
    strangerOutcome = e.shortMessage || e.message;
    strangerRejected = permissionErr(e) || /not authorized|permission/i.test(strangerOutcome);
  }
  results.strangerRejected = strangerRejected;
  console.log(`      stranger self-tx ........... ${strangerRejected ? "REJECTED ✓" : "??? ✗"}`);
  console.log(`      -> ${strangerOutcome}`);

  console.log("");
  console.log("------------------------------------------------------------");
  const pass =
    results.bootComplete && results.adminCanTransact && results.strangerRejected;
  console.table(results);
  console.log(pass ? "  RESULT: ENHANCED PERMISSIONING ENFORCED ✓" : "  RESULT: NOT FULLY ENFORCED ✗");
  console.log("============================================================");
  process.exitCode = pass ? 0 : 1;
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
