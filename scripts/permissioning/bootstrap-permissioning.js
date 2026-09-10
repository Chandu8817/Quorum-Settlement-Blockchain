/**
 * VittaGems — GoQuorum Enhanced (v2) Permissioning Bootstrap
 * =========================================================
 * Deploys the standard GoQuorum permissioning contract suite, wires it together
 * via PermissionsUpgradable.init(), and writes permission-config.json into every
 * node's data directory plus config/.
 *
 * MUST be run while the network is up but BEFORE permission-config.json is in
 * place (i.e. enhanced permissioning not yet active) — the deploying account
 * needs to be able to transact freely.
 *
 * Deploy order (constructor dependencies):
 *   1. PermissionsUpgradable(guardian)
 *   2. {Org,Role,Account,Voter,Node}Manager(upgradable)
 *   3. PermissionsImplementation(upgradable, org, role, account, voter, node)
 *   4. PermissionsInterface(upgradable)
 *   5. upgradable.init(interface, impl)   <- from guardian
 *
 * On the NEXT node restart (with permission-config.json present + --permissioned)
 * GoQuorum performs the one-time network bootstrap itself: creates nwAdminOrg,
 * assigns nwAdminRole to every account in `accounts`, and imports static-nodes.
 *
 * Run: npx hardhat run scripts/permissioning/bootstrap-permissioning.js --network quorum_local
 */
const hre = require("hardhat");
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const ROOT = path.join(__dirname, "..", "..");
const CONFIG_DIR = path.join(ROOT, "config");
const NETWORK_DIR = path.join(ROOT, "network");
const DEPLOY_DIR = path.join(ROOT, "deployments");

// Enhanced-permissioning policy parameters (see GoQuorum docs).
const NW_ADMIN_ORG = "VITTAGEMS";
const NW_ADMIN_ROLE = "NWADMIN";
const ORG_ADMIN_ROLE = "ORGADMIN";
const SUB_ORG_BREADTH = 3;
const SUB_ORG_DEPTH = 4;

const GAS = 60_000_000; // generous; network runs gasprice 0

async function deploy(name, args = []) {
  const factory = await hre.ethers.getContractFactory(
    `contracts/permissioning/quorum/${name}.sol:${name}`
  );
  const c = await factory.deploy(...args, { gasLimit: GAS });
  await c.waitForDeployment();
  const addr = await c.getAddress();
  console.log(`  ✓ ${name.padEnd(26)} ${addr}`);
  return c;
}

function loadOperationalAccounts() {
  const p = path.join(CONFIG_DIR, "operational-accounts.json");
  if (!fs.existsSync(p)) {
    console.log("  operational-accounts.json missing — generating it now...");
    execSync(`node ${path.join(__dirname, "gen-operational-accounts.js")}`, {
      stdio: "inherit",
    });
  }
  const data = JSON.parse(fs.readFileSync(p, "utf8"));
  return Object.values(data.accounts).map((a) => a.address);
}

function nodeDataDirs() {
  return fs
    .readdirSync(NETWORK_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => path.join(NETWORK_DIR, d.name, "data"))
    .filter((p) => fs.existsSync(p));
}

/**
 * Accounts derived from each node's devp2p nodekey.
 *
 * These MUST be permissioned. GoQuorum signs the one-time network bootstrap
 * transactions (setPolicy/init/addAdminNode/addAdminAccount/updateNetworkBootStatus)
 * with `stack.GetNodeKey()` — i.e. every node submits them from its OWN nodekey
 * account. Once one node's updateNetworkBootStatus flips networkBoot to true,
 * any still-in-flight bootstrap tx from an unpermissioned node account is
 * *denied* (not merely reverted), which makes the containing block invalid:
 *
 *   ########## BAD BLOCK #########
 *   Error: could not apply tx 0 [...]: account does not have permission
 *
 * and the chain halts. Including all node accounts removes that failure mode.
 */
function nodeKeyAccounts() {
  const out = [];
  for (const dir of nodeDataDirs()) {
    const nk = path.join(dir, "nodekey");
    if (!fs.existsSync(nk)) continue;
    const key = fs.readFileSync(nk, "utf8").trim();
    out.push(new hre.ethers.Wallet("0x" + key).address);
  }
  return out;
}

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const guardian = deployer.address;
  const chainId = (await hre.ethers.provider.getNetwork()).chainId.toString();

  console.log("============================================================");
  console.log("  VittaGems — Enhanced (v2) Permissioning Bootstrap");
  console.log("============================================================");
  console.log(`  Network:   ${hre.network.name}`);
  console.log(`  Chain ID:  ${chainId}`);
  console.log(`  Guardian:  ${guardian}`);
  console.log("");

  // Refuse to run if enhanced permissioning already looks active.
  const existing = path.join(CONFIG_DIR, "permission-config.json");
  if (fs.existsSync(existing)) {
    console.log(`  ⚠ ${existing} already exists.`);
    console.log("    If you are re-bootstrapping a fresh chain, delete it (and the copies");
    console.log("    under network/*/data/) first, then re-run. Aborting to be safe.");
    process.exit(1);
  }

  console.log("  Deploying permissioning suite...");
  const upgradable = await deploy("PermissionsUpgradable", [guardian]);
  const upgradableAddr = await upgradable.getAddress();

  const orgMgr = await deploy("OrgManager", [upgradableAddr]);
  const roleMgr = await deploy("RoleManager", [upgradableAddr]);
  const acctMgr = await deploy("AccountManager", [upgradableAddr]);
  const voterMgr = await deploy("VoterManager", [upgradableAddr]);
  const nodeMgr = await deploy("NodeManager", [upgradableAddr]);

  const impl = await deploy("PermissionsImplementation", [
    upgradableAddr,
    await orgMgr.getAddress(),
    await roleMgr.getAddress(),
    await acctMgr.getAddress(),
    await voterMgr.getAddress(),
    await nodeMgr.getAddress(),
  ]);

  const iface = await deploy("PermissionsInterface", [upgradableAddr]);

  console.log("");
  console.log("  Linking interface + implementation via PermissionsUpgradable.init()...");
  const initTx = await upgradable.init(
    await iface.getAddress(),
    await impl.getAddress(),
    { gasLimit: 4_500_000 }
  );
  const initRcpt = await initTx.wait();
  console.log(`  ✓ init() mined in block ${initRcpt.blockNumber ?? "?"}`);

  // sanity: read back wiring
  const wiredImpl = await upgradable.getPermImpl();
  const wiredIface = await upgradable.getPermInterface();
  if (
    wiredImpl.toLowerCase() !== (await impl.getAddress()).toLowerCase() ||
    wiredIface.toLowerCase() !== (await iface.getAddress()).toLowerCase()
  ) {
    throw new Error("PermissionsUpgradable wiring mismatch after init()");
  }
  console.log("  ✓ wiring verified on-chain");

  const bootStatus = await iface.getNetworkBootStatus();
  console.log(`  network boot status (expected false pre-restart): ${bootStatus}`);

  // Network admins = the settlement service accounts + every node's nodekey
  // account (see nodeKeyAccounts() for why the latter are mandatory).
  const opAccounts = loadOperationalAccounts();
  const nodeAccounts = nodeKeyAccounts();
  const seen = new Set();
  const accounts = [...opAccounts, ...nodeAccounts].filter((a) => {
    const k = a.toLowerCase();
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
  console.log("");
  console.log(`  network admin accounts (${accounts.length}):`);
  for (const a of opAccounts) console.log(`    operational  ${a}`);
  for (const a of nodeAccounts) {
    if (!opAccounts.some((o) => o.toLowerCase() === a.toLowerCase())) {
      console.log(`    node key     ${a}`);
    }
  }

  const permissionConfig = {
    permissionModel: "v2",
    upgradableAddress: upgradableAddr.toLowerCase(),
    interfaceAddress: (await iface.getAddress()).toLowerCase(),
    implAddress: (await impl.getAddress()).toLowerCase(),
    nodeMgrAddress: (await nodeMgr.getAddress()).toLowerCase(),
    accountMgrAddress: (await acctMgr.getAddress()).toLowerCase(),
    roleMgrAddress: (await roleMgr.getAddress()).toLowerCase(),
    voterMgrAddress: (await voterMgr.getAddress()).toLowerCase(),
    orgMgrAddress: (await orgMgr.getAddress()).toLowerCase(),
    nwAdminOrg: NW_ADMIN_ORG,
    nwAdminRole: NW_ADMIN_ROLE,
    orgAdminRole: ORG_ADMIN_ROLE,
    accounts: accounts.map((a) => a.toLowerCase()),
    subOrgBreadth: SUB_ORG_BREADTH,
    subOrgDepth: SUB_ORG_DEPTH,
  };

  const json = JSON.stringify(permissionConfig, null, 2) + "\n";

  const targets = [path.join(CONFIG_DIR, "permission-config.json")];
  for (const dir of nodeDataDirs()) targets.push(path.join(dir, "permission-config.json"));
  for (const t of targets) {
    fs.writeFileSync(t, json);
    console.log(`  wrote ${path.relative(ROOT, t)}`);
  }

  if (!fs.existsSync(DEPLOY_DIR)) fs.mkdirSync(DEPLOY_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(DEPLOY_DIR, "permissioning-v2-deployment.json"),
    JSON.stringify(
      {
        model: "goquorum-enhanced-v2",
        network: hre.network.name,
        chainId,
        guardian,
        deployedAt: new Date().toISOString(),
        policy: {
          nwAdminOrg: NW_ADMIN_ORG,
          nwAdminRole: NW_ADMIN_ROLE,
          orgAdminRole: ORG_ADMIN_ROLE,
          subOrgBreadth: SUB_ORG_BREADTH,
          subOrgDepth: SUB_ORG_DEPTH,
        },
        contracts: {
          PermissionsUpgradable: upgradableAddr,
          PermissionsInterface: await iface.getAddress(),
          PermissionsImplementation: await impl.getAddress(),
          OrgManager: await orgMgr.getAddress(),
          RoleManager: await roleMgr.getAddress(),
          AccountManager: await acctMgr.getAddress(),
          VoterManager: await voterMgr.getAddress(),
          NodeManager: await nodeMgr.getAddress(),
        },
        networkAdminAccounts: accounts,
        operationalAccounts: opAccounts,
        nodeKeyAccounts: nodeAccounts,
      },
      null,
      2
    ) + "\n"
  );
  console.log(`  wrote deployments/permissioning-v2-deployment.json`);

  console.log("");
  console.log("============================================================");
  console.log("  Bootstrap complete. Next:");
  console.log("    1. docker compose -f docker/docker-compose.yml down");
  console.log("    2. docker compose -f docker/docker-compose.yml up -d   (nodes now run --permissioned + see permission-config.json)");
  console.log("    3. wait for validator1 log: 'permission service: is now ready'");
  console.log("    4. npx hardhat run scripts/permissioning/verify-permissioning.js --network quorum_local");
  console.log("============================================================");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
