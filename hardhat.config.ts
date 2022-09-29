import * as dotenv from "dotenv";

import "@nomiclabs/hardhat-waffle";
import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-deploy"

import "hardhat-contract-sizer"
import "hardhat-storage-layout"
import "./tasks/aludel"

dotenv.config();

const forkingUrl = process.env.FORK_URL || ''
const mnemonic = process.env.DEV_MNEMONIC || ''
const privateKey = process.env.PRIVATE_KEY || ''
const goerliUrl = process.env.GOERLI_RPC || ''
const infuraKey = process.env.ETHERSCAN_API_KEY || ''
const polyscanApiKey = process.env.POLYGON_MUMBAI_API_KEY || ''
const mumbaiUrl = process.env.MUMBAI_RPC || ''

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.6",
    settings: {
      outputSelection: {
        "*": {
            "*": ["storageLayout"],
        },
      },
    }
  },
  networks: {
    hardhat: {
      forking: {
        url: forkingUrl,
        blockNumber: 14169000
      },
      accounts: {
        mnemonic
      }
    },
    goerli: {
      url: goerliUrl,
      accounts: {
        mnemonic
      },
      live: true,
      saveDeployments: true,
      tags: ['staging']
    },
    mumbai: {
      url: mumbaiUrl,
      accounts: {
        mnemonic
      },
      saveDeployments: true
    },
    avalanche: {
      url: 'https://api.avax.network/ext/bc/C/rpc',
      chainId: 43114,
      accounts: {
        mnemonic
      }
    },
    localhost: {
      url: 'http://127.0.0.1:8545',
      accounts: {
        mnemonic
      },
    }
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS ? true : false,
    currency: "USD",
  },
  namedAccounts: {
    deployer: {
      default: 0
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
      polygonMumbai: polyscanApiKey
    }
  },
  
  paths: {
    artifacts: "./out",
    sources: "./src/contracts",
  },
};

export default config;
