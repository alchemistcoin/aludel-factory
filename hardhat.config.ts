import * as dotenv from "dotenv";

import "@nomiclabs/hardhat-waffle";
import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomicfoundation/hardhat-chai-matchers";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-deploy";

import "hardhat-contract-sizer";
import "hardhat-storage-layout";
import "./tasks/aludel";

dotenv.config();

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
const forkingUrl = process.env.FORK_URL || "";
const mnemonic = process.env.DEV_MNEMONIC || "";
const rinkebyUrl = process.env.RINKEBY_URL || "";
const goerliUrl = process.env.GOERLI_URL || "";
const infuraKey = process.env.ETHERSCAN_API_KEY || "";
const polyscanApiKey = process.env.POLYGON_MUMBAI_API_KEY || "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.17",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200,
      },
      outputSelection: {
        "*": {
          "*": ["storageLayout"],
        },
      },
    },
  },
  networks: {
    hardhat: {
      forking: {
        url: forkingUrl,
        blockNumber: 14169000,
      },
      accounts: {
        mnemonic,
      },
    },
    ropsten: {
      url: process.env.ROPSTEN_URL || "",
      accounts: {
        mnemonic,
      },
      live: true,
      saveDeployments: true,
      tags: ["staging"],
    },
    goerli: {
      url: goerliUrl,
      accounts: {
        mnemonic,
      },
      live: true,
      saveDeployments: true,
      tags: ["staging"],
    },
    rinkeby: {
      url: rinkebyUrl,
      accounts: {
        mnemonic,
      },
      live: true,
      saveDeployments: true,
      tags: ["staging"],
    },
    mumbai: {
      url: process.env.MUMBAI_URL || "",
      accounts: {
        mnemonic,
      },
      saveDeployments: true,
    },
    polygon: {
      url: process.env.POLYGON_URL || "",
      accounts: {
        mnemonic,
      },
      saveDeployments: true,
    },
    avalanche: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      chainId: 43114,
      accounts: {
        mnemonic,
      },
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      accounts: {
        mnemonic,
      },
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    currency: "USD",
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    dev: {
      // Default to 1
      default: 1,
      // dev address mainnet
      // 1: "",
    },
  },
  etherscan: {
    apiKey: {
      goerli: infuraKey,
      rinkeby: infuraKey,
      polygonMumbai: polyscanApiKey,
    },
  },

  paths: {
    artifacts: "./out",
    sources: "./src/contracts",
  },
  typechain: {
    outDir: "./typechain-types",
  },
};

export default config;
