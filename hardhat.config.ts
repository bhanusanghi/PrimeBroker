import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-ethers"
import "@openzeppelin/hardhat-upgrades"
import "@typechain/hardhat"
import "hardhat-contract-sizer"
import "hardhat-dependency-compiler"
import "hardhat-gas-reporter"
import "solidity-coverage"
require("dotenv").config()

const config: HardhatUserConfig = {
  solidity: "0.8.17",
  networks: {
    mainnet: {
      timeout: 60000,
      chainId: 1,
      url: process.env.RPC_URL || `https://mainnet.infura.io/v3/${process.env.MAINNET_KEY}`,
    },
    hardhat: {
      allowUnlimitedContractSize: true,
      initialBaseFeePerGas: 0,
      chainId: 1337,
      forking:
      {
        enabled: true,
        url: process.env.OPTIMISM_MAINNET_KEY || '',
        // blockNumber: 513665,
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
  paths: {
    // tests: "./test",
  },
  mocha: {
    timeout: 100000000
  },
};

export default config;
