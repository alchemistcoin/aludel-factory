import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-deploy"

import "./tasks/aludel"

dotenv.config();

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
const forkingUrl = process.env.FORK_URL || ''
const mnemonic = process.env.DEV_MNEMONIC || ''
const privateKey = process.env.PRIVATE_KEY || ''
const rinkebyUrl = process.env.RINKEBY_URL || ''

const config: HardhatUserConfig = {
  solidity: "0.8.12",
  networks: {
    hardhat: {
      forking: {
        url: forkingUrl,
        blockNumber: 14169000
      },
    },
    ropsten: {
      url: process.env.ROPSTEN_URL || "",
      accounts: {
        mnemonic
      },
      live: true,
      saveDeployments: true,
      tags: ['staging']
    },
    rinkeby: {
      url: rinkebyUrl,
      accounts: {
        mnemonic
      },
      live: true,
      saveDeployments: true,
      tags: ['staging']
    },
    mumbai: {
      url: process.env.MUMBAI_URL || '',
      accounts: {
        mnemonic
      }
    }
  
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
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
      rinkeby: process.env.ETHERSCAN_API_KEY,
      polygonMumbai: process.env.POLYGON_MUMBAI_API_KEY
    }
  },
  
  paths: {
    sources: "./src/contracts"
  },
};

export default config;
