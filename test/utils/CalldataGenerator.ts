import { expect } from "chai"
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
import { artifacts, ethers, network, waffle } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { erc20 } from "../integrations/addresses";
import { MarginManager, MarginAccount, ERC20, RiskManager } from "../../typechain-types";
import { metadata } from "../integrations/PerpfiOptimismMetadata";
import { abi as perpVaultAbi } from "../external/abi/perpVault";
import { abi as perpClearingHouseAbi } from "../external/abi/clearingHouse";
import { abi as perpAccountBalanceAbi } from "../external/abi/accountBalance";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { PERP, ERC20 as ERC20Hash, SNXUNI, TRANSFERMARGIN } from "./constants";
import { mintToAccountSUSD } from "./helpers";
import { boolean } from "hardhat/internal/core/params/argumentTypes";
import dotenv from "dotenv";
dotenv.config();

export const getErc20ApprovalCalldata = async (address: string, value: BigNumber) => {
  const ERC20 = (
    await artifacts.readArtifact(
      "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
    )
  ).abi;
  let iface = new ethers.utils.Interface(ERC20);
  return iface.encodeFunctionData("approve", [address, value])
}

export const getVaultDepositCalldata = async (token: string, value: BigNumber) => {
  const PerpVault = (
    await artifacts.readArtifact("contracts/Interfaces/Perpfi/IVault.sol:IVault")
  ).abi;
  let iface = new ethers.utils.Interface(PerpVault);
  return iface.encodeFunctionData("deposit", [token, value])
}

export const getOpenPerpPositionCalldata = async (
  baseToken: string,
  isBaseToQuote: boolean,
  isExactInput: boolean,
  oppositeAmountBound: BigNumber,
  amount: BigNumber,
  sqrtPriceLimitX96: BigNumber,
  deadline: BigNumber,
  referralCode = ethers.constants.HashZero,
) => {
  const IClearingHouse = (
    await artifacts.readArtifact("contracts/Interfaces/Perpfi/IClearingHouse.sol:IClearingHouse")
  ).abi;
  let iface = new ethers.utils.Interface(IClearingHouse);
  return iface.encodeFunctionData("openPosition", [baseToken, isBaseToQuote, isExactInput, oppositeAmountBound, amount, sqrtPriceLimitX96, deadline, referralCode])
}
export const perpOpenPositionCallData = async (
  baseToken: string,
  isBaseToQuote: boolean,
  isExactInput: boolean,
  oppositeAmountBound: BigNumber,
  amount: BigNumber,
  sqrtPriceLimitX96: BigNumber,
  deadline: BigNumber,
  referralCode = ethers.constants.HashZero,
) => {
  const IClearingHouse = (
    await artifacts.readArtifact("contracts/Interfaces/Perpfi/IClearingHouse.sol:IClearingHouse")
  ).abi;
  const iface = new ethers.utils.Interface(IClearingHouse)

  const data = await iface.encodeFunctionData("openPosition", [{
    baseToken: baseToken,
    isBaseToQuote: isBaseToQuote, // quote to base
    isExactInput: isExactInput,
    oppositeAmountBound: oppositeAmountBound, // exact output (base)
    amount: amount,
    sqrtPriceLimitX96: sqrtPriceLimitX96,
    deadline: deadline,
    referralCode: referralCode
  }])
  return data
}
export const transferMarginDataSNX = async (address: any, amount: any) => {
  const IFuturesMarketABI = (
    await artifacts.readArtifact("contracts/Interfaces/SNX/IFuturesMarket.sol:IFuturesMarket")
  ).abi;
  const iFutures = new ethers.utils.Interface(IFuturesMarketABI)
  const data = await iFutures.encodeFunctionData("transferMargin", [amount])
  return data
}
export const openPositionDataSNX = async (sizeDelta: any, trackingCode: any) => {
  const IFuturesMarketABI = (
    await artifacts.readArtifact("contracts/Interfaces/SNX/IFuturesMarket.sol:IFuturesMarket")
  ).abi;
  const iFutures = new ethers.utils.Interface(IFuturesMarketABI)
  const data = await iFutures.encodeFunctionData("modifyPositionWithTracking", [sizeDelta, trackingCode])
  return data
}
