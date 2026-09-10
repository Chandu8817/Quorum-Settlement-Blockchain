/**
 * Generates config/operational-accounts.json — a FIXED set of dev keypairs for
 * the settlement network's service accounts (treasury/compliance/settlement
 * agent/auditor/partners).
 *
 * Why fixed keys: once GoQuorum enhanced (v2) permissioning is active, an
 * account that is not known to the permissioning contracts cannot send any
 * transaction. The old lifecycle test used `Wallet.createRandom()` every run,
 * which is incompatible with account-level permissioning. These deterministic
 * accounts are listed in permission-config.json so the bootstrap grants them
 * network-admin access.
 *
 *   !! DEVELOPMENT KEYS ONLY — never use on a shared or production network. !!
 *
 * Idempotent: does nothing if the file already exists (delete it to regenerate).
 * Run: node scripts/permissioning/gen-operational-accounts.js
 */
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const OUT = path.join(__dirname, "..", "..", "config", "operational-accounts.json");

const ROLES = [
  { key: "deployer", note: "network admin / guardian / contract deployer (same key as validator1 nodekey)" },
  { key: "treasuryAdmin", note: "TREASURY_ADMIN on VittaGemsSettlement" },
  { key: "complianceOperator", note: "COMPLIANCE_OPERATOR" },
  { key: "settlementAgent", note: "SETTLEMENT_AGENT" },
  { key: "auditor", note: "AUDITOR" },
  { key: "partner1", note: "approved partner (US provider)" },
  { key: "partner2", note: "approved partner (regional)" },
];

// validator1 nodekey — already used as the deployer everywhere in this repo.
const DEPLOYER_PK = "0x4bfa5480174e5c4c48f68d4f6eb42f05edb2c689c06c6291f4387d43f9dfe196";

if (fs.existsSync(OUT)) {
  console.log(`operational-accounts.json already exists at ${OUT} — leaving it untouched.`);
  process.exit(0);
}

const accounts = {};
for (const { key, note } of ROLES) {
  let wallet;
  if (key === "deployer") {
    wallet = new ethers.Wallet(DEPLOYER_PK);
  } else {
    wallet = ethers.Wallet.createRandom();
  }
  accounts[key] = {
    address: wallet.address,
    privateKey: wallet.privateKey,
    note,
  };
}

const payload = {
  _WARNING: "DEVELOPMENT KEYS ONLY — do not use on any shared/production network",
  generatedAt: new Date().toISOString(),
  accounts,
};

fs.writeFileSync(OUT, JSON.stringify(payload, null, 2) + "\n");
console.log(`Wrote ${OUT}`);
for (const [k, v] of Object.entries(accounts)) {
  console.log(`  ${k.padEnd(20)} ${v.address}`);
}
