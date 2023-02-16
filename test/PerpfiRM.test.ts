import { expect } from "chai"
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
import { artifacts, ethers, network } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { erc20 } from "./integrations/addresses";
import { MarginManager, MarginAccount, ERC20 } from "../typechain-types";
import { metadata } from "./integrations/PerpfiOptimismMetadata";
import { abi as perpVaultAbi } from "./external/abi/perpVault";
import { abi as perpClearingHouseAbi } from "./external/abi/clearingHouse";
import { abi as perpAccountBalanceAbi } from "./external/abi/accountBalance";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { perpOpenPositionCallData, getVaultDepositCalldata, getErc20ApprovalCalldata } from "./utils/CalldataGenerator";
import { PERP, PERP_MARKET_KEY_AAVE, ERC20 as ERC20Hash } from "./utils/constants";
import dotenv from "dotenv";
dotenv.config();

const ETHER = 10 ** 18
let vault: Contract;
let LPToken: Contract;
type Contracts = {
  marginManager: MarginManager;
  marginAccount: MarginAccount;
  perp: {
    vault: any;
    clearingHouse: any;
    accountBalance: any
  }
  erc20: {
    usdc: ERC20;
    frax: ERC20;
  },
}

let contracts: Contracts;
let PerpfiRiskManager: Contract;
let admin: SignerWithAddress, bob: SignerWithAddress;
const fraxMetadata = metadata.collaterals[1];
/**
 * @notice fork network at block number given
 */
const forkAtBlock = async (block?: number) => {
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: process.env.ARCHIVE_NODE_URL_L2
        },
      },
    ],
  });
};

async function initializeContractsFixture() {
  const protocolRiskManagerFactory = await ethers.getContractFactory("PerpfiRiskManager");
  PerpfiRiskManager = await protocolRiskManagerFactory.deploy(erc20.usdc, metadata.contracts.AccountBalance.address, metadata.contracts.Exchange.address)
}

describe("MarginManager", () => {
  beforeEach(async () => {
    // await resetFork();
    await forkAtBlock();
    [admin, bob] = await ethers.getSigners()
    await initializeContractsFixture();
    // contracts = await loadFixture(initializeContractsFixture);
    // account with usdc - 0xebe80f029b1c02862b9e8a70a7e5317c06f62cae
  })
  describe("Fork test", () => {
    it.only("should allow opening a long position on perp directly", async () => {
      const baseToken = "0x34235C8489b06482A99bb7fcaB6d7c467b92d248";
      const parsedAmount = ethers.utils.parseUnits("10000", 6)
      const _perpOpenPositionCallData = await perpOpenPositionCallData(
        "0x34235C8489b06482A99bb7fcaB6d7c467b92d248",
        false,
        true,
        ethers.BigNumber.from('0'),
        ethers.utils.parseUnits("5000", 6),
        ethers.BigNumber.from('0'),
        ethers.constants.MaxUint256,
        ethers.constants.HashZero)
      //verifyTrade
      console.log(PerpfiRiskManager.address, "prm", _perpOpenPositionCallData)
      const out = await PerpfiRiskManager.verifyTrade(metadata.contracts.ClearingHouse.address, [metadata.contracts.ClearingHouse.address], [_perpOpenPositionCallData])
      console.log("done", out)
    });
  });
})
