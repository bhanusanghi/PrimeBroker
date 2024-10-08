import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-ethers"
import "@openzeppelin/hardhat-upgrades"
import "@typechain/hardhat"
import "@nomiclabs/hardhat-waffle";
import "hardhat-contract-sizer"
import "hardhat-dependency-compiler"
import "hardhat-gas-reporter"
import "solidity-coverage"
import dotenv from "dotenv";
dotenv.config();

const config: HardhatUserConfig = {

  networks: {
    mainnet: {
      timeout: 60000,
      chainId: 1,
      url: 'process.env.ARCHIVE_NODE_URL_L2',
    },
    hardhat: {
      allowUnlimitedContractSize: true,
      initialBaseFeePerGas: 0,
      chainId: 1337,
      forking:
      {
        enabled: true,
        // url: process.env.OPTIMISM_MAINNET_KEY || '',process.env.ARCHIVE_NODE_URL_L2 || 
        url: process.env.ARCHIVE_NODE_URL_L2 || '',
        // blockNumber: number,
      }
    }

    // 'optimism': {
    //   url: "https://mainnet.optimism.io",
    //   // accounts: [privateKey1, privateKey2, ...]
    // },
    // // for testnet
    // 'optimism-goerli': {
    //   url: "https://goerli.optimism.io",
    //   // accounts: [privateKey1, privateKey2, ...]
    // },
    // // for the local dev environment
    // 'optimism-local': {
    //   url: "http://localhost:8545",
    //   // accounts: [privateKey1, privateKey2, ...]
    // },
  },
  dependencyCompiler: {
    paths: [
      // "@perp/perp-oracle-contract/contracts/ChainlinkPriceFeedV2.sol"
    ]
  },
  solidity: {
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
    compilers: [
      {
        version: "0.8.0",
      },
      {
        version: "0.8.10",
      },
      {
        version: "0.8.17",
      }
    ],
  },
  mocha: {
    timeout: 100000000
  },
};

export default config;
