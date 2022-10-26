import {
  Vault, IInterestRateModel, LinearInterestRateModel, MockERC20
} from "../typechain-types";
import { BigNumber } from "ethers";
import { ethers } from "hardhat"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");


type VaultFixture = {
  vault: Vault;
  interestRateModel: IInterestRateModel;
  erc20: {
    mock1: MockERC20;
    mock2: MockERC20;
  }
}

export const getVaultFixture = async (whitelistedLender: string, whitelistedBorrower: string): Promise<VaultFixture> => {
  const interestRateModelFactory = await ethers.getContractFactory("LinearInterestRateModel");
  const optimalUse = ethers.BigNumber.from("9000");
  const rBase = ethers.BigNumber.from("0");
  const rSlope1 = ethers.BigNumber.from("200");
  const rSlope2 = ethers.BigNumber.from("1000");
  const interestRateModel: LinearInterestRateModel = await interestRateModelFactory.deploy(
    optimalUse,
    rBase,
    rSlope1,
    rSlope2
  )
  const MockERC20Factory = await ethers.getContractFactory("MockERC20");
  const mock1 = await MockERC20Factory.deploy("mock1", "mk1")
  const mock2 = await MockERC20Factory.deploy("mock2", "mk2");

  const maxExpectedLiquidity: BigNumber = ethers.constants.MaxUint256;
  const VaultFactory = await ethers.getContractFactory("Vault");
  const vault = await VaultFactory.deploy(
    mock1.address, "LPToken", "LPT", interestRateModel.address, maxExpectedLiquidity
  )
  await vault.addLendingAddress(whitelistedLender)
  await vault.addRepayingAddress(whitelistedBorrower)
  return {
    vault,
    interestRateModel,
    erc20: {
      mock1,
      mock2,
    }
  }
}
