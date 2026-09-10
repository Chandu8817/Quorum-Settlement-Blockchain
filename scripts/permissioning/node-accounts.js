// Prints the Ethereum account derived from each node's devp2p nodekey.
// GoQuorum signs the one-time permissioning bootstrap transactions with
// stack.GetNodeKey(), so every one of these accounts must be permissioned or
// the bootstrap block is rejected ("account does not have permission").
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const NETWORK_DIR = path.join(__dirname, "..", "..", "network");
for (const d of fs.readdirSync(NETWORK_DIR)) {
  const nk = path.join(NETWORK_DIR, d, "data", "nodekey");
  if (!fs.existsSync(nk)) continue;
  const key = fs.readFileSync(nk, "utf8").trim();
  console.log(d.padEnd(12), new ethers.Wallet("0x" + key).address);
}
