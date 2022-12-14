require("@nomiclabs/hardhat-waffle");
require("hardhat-deploy");
require("solidity-coverage");
require("hardhat-deploy-ethers");
require("hardhat-abi-exporter");
require("hardhat-gas-reporter");
require("hardhat-contract-sizer");
require("hardhat-storage-layout");
require("dotenv").config();
const { DEPLOY_KEY } = require("./env.json");

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.6.12",
        settings: {
          evmVersion: "constantinople",
          optimizer: {
            enabled: true,
            runs: 1,
          },
          outputSelection: {
            "*": {
              "*": ["storageLayout"],
            },
          },
        },
      },
    ],
  },
  networks: {
    localhost: {
      live: false,
      saveDeployments: true,
      tags: ["test", "local"],
    },
    hardhat: {
      hardfork: "london",
      live: false,
      saveDeployments: true,
      tags: ["test", "local"],
      accounts: {
        accountsBalance: "10000000000000000000000000000000000000000000000000000000000000000",
      },
      allowUnlimitedContractSize: true,
    },
    cypress: {
      url: "https://klaytn05.fandom.finance",
      chainId: 8217,
      gas: 20000000,
      gasPrice: 250000000000,
      accounts: [DEPLOY_KEY],
      live: true,
      saveDeployments: true,
      tags: ["mainnet"],
    },
    baobab: {
      url: "https://api.baobab.klaytn.net:8651",
      chainId: 1001,
      gas: 20000000,
      gasPrice: 250000000000,
      accounts: [DEPLOY_KEY],
      live: true,
      saveDeployments: true,
      tags: ["test", "testnet"],
    },
    coverage: {
      url: "http://localhost:8555",
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  abiExporter: {
    path: "./abi",
    clear: true,
    flat: true,
    only: [],
    except: [],
    spacing: 2,
  },
};
