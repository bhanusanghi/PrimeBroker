
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai"
import { BigNumber } from "ethers";
import { parseEther, parseUnits } from "ethers/lib/utils"
import { ethers } from "hardhat"
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
import { timeTravel } from "./utils/helpers";
import {
  Vault, IInterestRateModel, LinearInterestRateModel,
  LPToken, MockERC20
} from "../typechain-types";
import { erc20 } from "./integrations/addresses";

type VaultFixture = {
  vault: Vault;
  interestRateModel: IInterestRateModel;
  erc20: {
    mock1: MockERC20;
    mock2: MockERC20;
    vaultLp: LPToken;
  }
}
let admin: SignerWithAddress, alice: SignerWithAddress, bob: SignerWithAddress;
let contracts: VaultFixture
const getVaultFixture = async (): Promise<VaultFixture> => {
  [admin, alice, bob] = await ethers.getSigners();
  const interestRateModelFactory = await ethers.getContractFactory("LinearInterestRateModel", admin);
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
  const vaultAsset = erc20.usdc;
  // 
  const LPTokenFactory = await ethers.getContractFactory("LPToken");
  const lpToken: LPToken = await LPTokenFactory.deploy("GigaBrainiac", "Goob", 18);
  // mock tokens
  const MockERC20Factory = await ethers.getContractFactory("MockERC20");
  const mock1 = await MockERC20Factory.deploy("mock1", "mk1")
  const mock2 = await MockERC20Factory.deploy("mock2", "mk2");

  const maxExpectedLiquidity = ethers.constants.MaxUint256;
  const VaultFactory = await ethers.getContractFactory("Vault");
  const vault = await VaultFactory.deploy(
    mock1.address, lpToken.address, interestRateModel.address, maxExpectedLiquidity
  )
  return {
    vault,
    interestRateModel,
    erc20: {
      mock1,
      mock2,
      vaultLp: lpToken
    }
  }
}

const fundWallet = async (user: SignerWithAddress, amount: BigNumber, token: MockERC20) => {
  token.connect(user).mint(user.address, amount);
}

describe.only("Vault test", async () => {

  beforeEach(async () => {
    contracts = await loadFixture(getVaultFixture);
    await fundWallet(bob, parseEther("100000"), contracts.erc20.mock1);
    // fundWithUsdc(bob);
    // fundWithSusd(bob);

    // fundWithUsdc(alice);
    // fundWithSusd(alice);
  })
  context("vault initialization check", () => {
    it("should have correct underlying asset set.", async () => {
      expect(await contracts.vault.asset()).to.eq(contracts.erc20.mock1.address);
    })
    it("should have correct lp token set.", async () => {
      expect(await contracts.vault.name()).to.eq(await contracts.erc20.vaultLp.name());
    })
    it("should have interest rate setup.", async () => {
      expect(await contracts.vault.getInterestRateModel()).to.eq(contracts.interestRateModel.address)
    })
    it("should have 0 shares minted", async () => {
      expect(await contracts.vault.totalSupply()).to.eq(BigNumber.from("0"))
    })
    it("should have 0 assets", async () => {
      expect(await contracts.vault.totalAssets()).to.eq(BigNumber.from("0"))
    })
    it("should have 0 expectedLiquidity", async () => {
      expect(await contracts.vault.expectedLiquidity()).to.eq(BigNumber.from("0"))
    })
    it("should have 1 RAY initial calcLinearCumulative_RAY", async () => {
      expect(await contracts.vault.calcLinearCumulative_RAY()).to.eq(parseUnits("1", 27));
    })
  })
  context.only("Vault functionality", () => {
    context("Interest and Shares.", () => {
      it("Should allow LPs to deposit right token and reflect properly", async () => {
        const depositAmount = parseEther("100");
        expect(await contracts.vault.previewDeposit(depositAmount)).to.eq(depositAmount)

        await contracts.erc20.mock1.connect(bob).approve(contracts.vault.address, depositAmount)
        await expect(await contracts.vault.connect(bob).deposit(depositAmount, bob.address)).to.emit(contracts.vault, "Deposit").withArgs(
          bob.address,
          bob.address,
          depositAmount,
          depositAmount,
        );
        expect(await contracts.vault.expectedLiquidity()).to.eq(depositAmount)
        expect(await contracts.vault.totalAssets()).to.eq(depositAmount)
        // expect(await contracts.erc20.vaultLp.balanceOf(bob.address)).to.eq(depositAmount)
      })
      // it("should revert on depositing wrong token", () => {

      // })
    })

  })




})
