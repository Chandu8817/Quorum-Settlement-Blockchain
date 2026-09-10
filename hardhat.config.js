require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: {
    compilers: [
      {
        // Application contracts (settlement, RBAC, legacy Besu-style permissioning)
        version: "0.8.20",
        settings: {
          optimizer: { enabled: true, runs: 200 },
          evmVersion: "istanbul",
        },
      },
      {
        // GoQuorum enhanced (v2) permissioning contract suite — pragma ^0.5.3.
        // Sources vendored under contracts/permissioning/quorum/.
        version: "0.5.17",
        settings: {
          optimizer: { enabled: true, runs: 200 },
          evmVersion: "istanbul",
        },
      },
    ],
  },
  networks: {
    quorum_validator1: {
      url: "http://localhost:8545",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: [process.env.PRIVATE_KEY || "0x4bfa5480174e5c4c48f68d4f6eb42f05edb2c689c06c6291f4387d43f9dfe196"],
    },
    quorum_validator2: {
      url: "http://localhost:8547",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: [process.env.PRIVATE_KEY || "0x4bfa5480174e5c4c48f68d4f6eb42f05edb2c689c06c6291f4387d43f9dfe196"],
    },
    quorum_validator3: {
      url: "http://localhost:8549",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: [process.env.PRIVATE_KEY || "0x4bfa5480174e5c4c48f68d4f6eb42f05edb2c689c06c6291f4387d43f9dfe196"],
    },
    quorum_rpc1: {
      url: "http://localhost:8551",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: [process.env.PRIVATE_KEY || "0x4bfa5480174e5c4c48f68d4f6eb42f05edb2c689c06c6291f4387d43f9dfe196"],
    },
    quorum_rpc2: {
      url: "http://localhost:8553",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: [process.env.PRIVATE_KEY || "0x4bfa5480174e5c4c48f68d4f6eb42f05edb2c689c06c6291f4387d43f9dfe196"],
    },
    quorum_local: {
      url: "http://localhost:8545",
      chainId: 7001,
      gasPrice: 0,
      gas: 8000000,
      hardfork: "istanbul",
      accounts: [process.env.PRIVATE_KEY || "0x4bfa5480174e5c4c48f68d4f6eb42f05edb2c689c06c6291f4387d43f9dfe196"],
    },
  },
};
