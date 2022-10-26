
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai"
import { BigNumber } from "ethers";
import { formatEther, parseEther, parseUnits } from "ethers/lib/utils"
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
  }
}
let admin: SignerWithAddress, alice: SignerWithAddress, bob: SignerWithAddress,
  borrower1: SignerWithAddress, borrower2: SignerWithAddress;
let contracts: VaultFixture
const getVaultFixture = async (): Promise<VaultFixture> => {
  [admin, alice, bob, borrower1, borrower2] = await ethers.getSigners();
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
  const MockERC20Factory = await ethers.getContractFactory("MockERC20");
  const mock1 = await MockERC20Factory.deploy("mock1", "mk1")
  const mock2 = await MockERC20Factory.deploy("mock2", "mk2");

  const maxExpectedLiquidity: BigNumber = ethers.constants.MaxUint256;
  const VaultFactory = await ethers.getContractFactory("Vault");
  const vault = await VaultFactory.deploy(
    mock1.address, "LPToken", "LPT", interestRateModel.address, maxExpectedLiquidity
  )
  await vault.addLendingAddress(admin.address)
  await vault.addRepayingAddress(admin.address)
  return {
    vault,
    interestRateModel,
    erc20: {
      mock1,
      mock2,
    }
  }
}

const fundWallet = async (user: SignerWithAddress, amount: BigNumber, token: MockERC20) => {
  token.connect(user).mint(user.address, amount);
}

// returns number of shares minted.
const depositInVault = async (user: SignerWithAddress, depositAmount: BigNumber): Promise<BigNumber> => {
  await contracts.erc20.mock1.connect(user).approve(contracts.vault.address, depositAmount)
  const initialShares = await contracts.vault.balanceOf(user.address)
  await contracts.vault.connect(user).deposit(depositAmount, user.address)
  const finalShares = await contracts.vault.balanceOf(user.address)
  return finalShares.sub(initialShares);
}

// returns amount of asset transferred to vault
const mintShares = async (user: SignerWithAddress, shares: BigNumber) => {
  await contracts.erc20.mock1.connect(user).approve(contracts.vault.address, ethers.constants.MaxInt256)
  const initialBalance = await contracts.erc20.mock1.balanceOf(user.address)
  await contracts.vault.connect(user).mint(shares, user.address)
  const finalBalance = await contracts.erc20.mock1.balanceOf(user.address)
  return initialBalance.sub(finalBalance);
}

// returns number of shares minted.
const withdraw = async (user: SignerWithAddress, withdrawAmount: BigNumber): Promise<BigNumber> => {
  await contracts.erc20.mock1.connect(user).approve(contracts.vault.address, withdrawAmount)
  const initialShares = await contracts.vault.balanceOf(user.address)
  await contracts.vault.connect(user).withdraw(withdrawAmount, user.address, user.address)
  const finalShares = await contracts.vault.balanceOf(user.address)
  return initialShares.sub(finalShares);
}

// returns amount of asset transferred to vault
const redeemShares = async (user: SignerWithAddress, shares: BigNumber) => {

  const initialBalance = await contracts.erc20.mock1.balanceOf(user.address)
  await contracts.vault.connect(user).redeem(shares, user.address, user.address)
  const finalBalance = await contracts.erc20.mock1.balanceOf(user.address)
  return finalBalance.sub(initialBalance);
}
const simulateLend = async (amount: BigNumber) => {
  await contracts.vault.connect(admin).borrow(borrower1.address, BigNumber.from("1"));
  // allow money repayment.
  // await contracts.erc20.mock1.connect(borrower1).approve(contracts.vault.address, ethers.constants.MaxInt256);
}

const simulateYield = async (amount: BigNumber) => {
  await contracts.vault.connect(admin).borrow(borrower1.address, BigNumber.from("1"));
  // allow money repayment.
  await contracts.erc20.mock1.connect(borrower1).approve(contracts.vault.address, ethers.constants.MaxInt256);
  await contracts.vault.connect(admin).repay(borrower1.address, BigNumber.from("1"), amount);
}

describe.only("Vault test", async () => {

  beforeEach(async () => {
    contracts = await loadFixture(getVaultFixture);
    await fundWallet(bob, parseEther("1000000"), contracts.erc20.mock1);
    await fundWallet(alice, parseEther("1000000"), contracts.erc20.mock1);
    await fundWallet(borrower1, parseEther("1000000"), contracts.erc20.mock1);
    await fundWallet(borrower2, parseEther("1000000"), contracts.erc20.mock1);
  })
  context("vault initialization check", () => {
    it("should have correct underlying asset set.", async () => {
      expect(await contracts.vault.asset()).to.eq(contracts.erc20.mock1.address);
    })
    // it("should have correct lp token address set.", async () => {
    //   expect(await contracts.vault.address).to.eq(await contracts.erc20.vaultLp.address);
    // })
    it("should have correct lp token set.", async () => {
      expect(await contracts.vault.name()).to.eq("LPToken");
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
    context("Interest and Shares single deposits.", () => {
      it("Should work for single deposit", async () => {
        const depositAmount = parseEther("100");
        // 0 circulation
        expect(await contracts.vault.totalSupply()).to.eq(BigNumber.from(0));
        // 0 shares for Bob
        expect(await contracts.vault.balanceOf(bob.address)).to.eq(BigNumber.from(0))
        expect(await contracts.vault.previewDeposit(depositAmount)).to.eq(depositAmount)

        await contracts.erc20.mock1.connect(bob).approve(contracts.vault.address, depositAmount)
        await expect(await contracts.vault.connect(bob).deposit(depositAmount, bob.address)).to
          .emit(contracts.vault, "Deposit").withArgs(
            bob.address,
            bob.address,
            depositAmount,
            depositAmount,
          )
          .emit(contracts.vault, "Transfer")
          .withArgs(
            ethers.constants.AddressZero,
            bob.address,
            depositAmount,
          );
        expect(await contracts.vault.expectedLiquidity()).to.eq(depositAmount)
        expect(await contracts.vault.totalAssets()).to.eq(depositAmount)
        expect(await contracts.vault.totalSupply()).to.eq(depositAmount)
        expect(await contracts.vault.balanceOf(bob.address)).to.eq(depositAmount)
      })
      it("Should work for single withdraw", async () => {
        const depositAmount = parseEther("100");
        await contracts.erc20.mock1.connect(bob).approve(contracts.vault.address, depositAmount)
        const bobInitialBalance = await contracts.erc20.mock1.balanceOf(bob.address)

        await contracts.vault.connect(bob).deposit(depositAmount, bob.address)

        const bobBalanceAfterDeposit = await contracts.erc20.mock1.balanceOf(bob.address)
        const bobShares = await contracts.vault.balanceOf(bob.address)
        expect(bobShares).to.eq(depositAmount)
        expect(bobBalanceAfterDeposit).to.eq(bobInitialBalance.sub(depositAmount))

        expect(await contracts.vault.previewWithdraw(depositAmount)).to.eq(bobShares)
        // test withdraw
        await contracts.vault.connect(bob).withdraw(depositAmount, bob.address, bob.address)
        const bobFinalBalance = await contracts.erc20.mock1.balanceOf(bob.address)
        expect(bobFinalBalance).to.eq(bobInitialBalance)
        // LP tokens burned ?
        expect(await contracts.vault.balanceOf(bob.address)).to.eq(0)

      })

      // add tests for mint/redeem

    })
    context("Interest and Shares multiple deposits with simulated yield", () => {
      // Scenario:
      // A = Alice, B = Bob
      //  ________________________________________________________
      // | Vault shares | A share | A assets | B share | B assets |
      // |========================================================|
      // | 1. Alice mints 2000 shares (costs 2000 tokens)         |
      // |--------------|---------|----------|---------|----------|
      // |         2000 |    2000 |     2000 |       0 |        0 |
      // |--------------|---------|----------|---------|----------|
      // | 2. Bob deposits 4000 tokens (mints 4000 shares)        |
      // |--------------|---------|----------|---------|----------|
      // |         6000 |    2000 |     2000 |    4000 |     4000 |
      // |--------------|---------|----------|---------|----------|
      // | 3. Vault mutates by +3000 tokens...                    |
      // |    (simulated yield returned from strategy)...         |
      // |--------------|---------|----------|---------|----------|
      // |         6000 |    2000 |     3000 |    4000 |     6000 |
      // |--------------|---------|----------|---------|----------|
      // | 4. Alice deposits 2000 tokens (mints 1333 shares)      |
      // |--------------|---------|----------|---------|----------|
      // |         7333 |    3333 |     4999 |    4000 |     6000 |
      // |--------------|---------|----------|---------|----------|
      // | 5. Bob mints 2000 shares (costs 3001 assets)           |
      // |    NOTE: Bob's assets spent got rounded up             |
      // |    NOTE: Alice's vault assets got rounded up           |
      // |--------------|---------|----------|---------|----------|
      // |         9333 |    3333 |     5000 |    6000 |     9000 |
      // |--------------|---------|----------|---------|----------|
      // | 6. Vault mutates by +3000 tokens...                    |
      // |    (simulated yield returned from strategy)            |
      // |    NOTE: Vault holds 17001 tokens, but sum of          |
      // |          assetsOf() is 17000.                          |
      // |--------------|---------|----------|---------|----------|
      // |         9333 |    3333 |     6071 |    6000 |    10929 |
      // |--------------|---------|----------|---------|----------|
      // | 7. Alice redeem 1333 shares (2428 assets)              |
      // |--------------|---------|----------|---------|----------|
      // |         8000 |    2000 |     3643 |    6000 |    10929 |
      // |--------------|---------|----------|---------|----------|
      // | 8. Bob withdraws 2928 assets (1608 shares)             |
      // |--------------|---------|----------|---------|----------|
      // |         6392 |    2000 |     3643 |    4392 |     8000 |
      // |--------------|---------|----------|---------|----------|
      // | 9. Alice withdraws 3643 assets (2000 shares)           |
      // |    NOTE: Bob's assets have been rounded back up        |
      // |--------------|---------|----------|---------|----------|
      // |         4392 |       0 |        0 |    4392 |     8001 |
      // |--------------|---------|----------|---------|----------|
      // | 10. Bob redeem 4392 shares (8001 tokens)               |
      // |--------------|---------|----------|---------|----------|
      // |            0 |       0 |        0 |       0 |        0 |
      // |______________|_________|__________|_________|__________|

      it("Mints Alice's shares on deposit", async () => {
        const assetsNeeded = await mintShares(alice, parseEther("2000"))
        expect(assetsNeeded).to.eq(parseEther("2000"))
        expect(await contracts.vault.totalAssets()).to.eq(parseEther("2000"))
        expect(await contracts.vault.totalSupply()).to.eq(parseEther("2000"))
      })
      it("Deposit's 4000 tokens from Bob", async () => {
        await mintShares(alice, parseEther("2000"))
        const sharesMinted = await depositInVault(bob, parseEther("4000"))
        expect(sharesMinted).to.eq(parseEther("4000"))
        expect(await contracts.vault.totalAssets()).to.eq(parseEther("6000"))
        expect(await contracts.vault.totalSupply()).to.eq(parseEther("6000"))
      })
      it("Simulates 3000 dollar yield", async () => {
        await mintShares(alice, parseEther("2000"))
        await depositInVault(bob, parseEther("4000"))
        await simulateYield(parseEther("3000"));
        expect(await contracts.vault.totalAssets()).to.eq(parseEther("9000"))
        expect(await contracts.vault.expectedLiquidity()).to.eq(parseEther("9000"))
        expect(await contracts.vault.totalSupply()).to.eq(parseEther("6000"))
        // Bob expected redeem value
        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(bob.address))).to.eq(parseEther("6000"))
        // Alice expected redeem value
        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(alice.address))).to.eq(parseEther("3000"))
      });
      it("Simulates 3000 dollar yield", async () => {
        await mintShares(alice, parseEther("2000"))
        await depositInVault(bob, parseEther("4000"))
        await simulateYield(parseEther("3000"));
        expect(await contracts.vault.totalAssets()).to.eq(parseEther("9000"))
        expect(await contracts.vault.expectedLiquidity()).to.eq(parseEther("9000"))
        expect(await contracts.vault.totalSupply()).to.eq(parseEther("6000"))
        // Bob expected redeem value
        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(bob.address))).to.eq(parseEther("6000"))
        // Alice expected redeem value
        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(alice.address))).to.eq(parseEther("3000"))
      });
      it("Alice deposits 2000 tokens", async () => {
        await mintShares(alice, parseEther("2000"))
        await depositInVault(bob, parseEther("4000"))
        await simulateYield(parseEther("3000"));
        const sharesMinted = await depositInVault(alice, parseEther("2000"))
        expect(sharesMinted).to.eq(BigNumber.from("1333333333333333333333"));
        expect(await contracts.vault.expectedLiquidity()).to.eq(parseEther("11000"));
        expect(await contracts.vault.totalAssets()).to.eq(parseEther("11000"));
        expect(await contracts.vault.totalSupply()).to.eq(parseEther("6000").add(BigNumber.from("1333333333333333333333")));

        expect(await contracts.vault.convertToAssets(await contracts.vault.balanceOf(bob.address)))
          .to.eq(
            parseEther("6000")
          )
        // Dust of 1/1e18 remains.
        expect(await contracts.vault.convertToAssets(await contracts.vault.balanceOf(alice.address)))
          .to.eq(
            BigNumber.from("4999999999999999999999")
          )
      });
      it("Bob mints 2000 shares", async () => {
        await mintShares(alice, parseEther("2000"))
        await depositInVault(bob, parseEther("4000"))
        await simulateYield(parseEther("3000"));
        await depositInVault(alice, parseEther("2000"))
        const assetsRequired = await mintShares(bob, parseEther("2000"));
        expect(assetsRequired).to.eq(BigNumber.from("3000000000000000000001"));

        expect(await contracts.vault.expectedLiquidity()).to.eq
          (
            parseEther("11000")
              .add(BigNumber.from("3000000000000000000001"))
          );

        expect(await contracts.vault.totalAssets()).to.eq
          (
            parseEther("11000")
              .add(BigNumber.from("3000000000000000000001"))
          );

        expect(await contracts.vault.totalSupply()).to.eq(
          parseEther("6000").
            add(BigNumber.from("1333333333333333333333")).
            add(parseEther("2000"))
        );

        expect(await contracts.vault.convertToAssets(await contracts.vault.balanceOf(bob.address)))
          .to.eq(
            parseEther("9000")
          )
        // // Dust of 1/1e18 remains.
        expect(await contracts.vault.convertToAssets(await contracts.vault.balanceOf(alice.address)))
          .to.eq(
            parseEther("5000")
          )
      });
      it("Simulates 3000 dollar yield", async () => {
        await mintShares(alice, parseEther("2000"))
        await depositInVault(bob, parseEther("4000"))
        await simulateYield(parseEther("3000"));
        await depositInVault(alice, parseEther("2000"))
        await mintShares(bob, parseEther("2000"));
        await simulateYield(parseEther("3000"));

        expect(await contracts.vault.expectedLiquidity()).to.eq
          (
            parseEther("11000")
              .add(BigNumber.from("3000000000000000000001"))
              .add(parseEther("3000"))
          );

        expect(await contracts.vault.totalAssets()).to.eq
          (
            parseEther("11000")
              .add(BigNumber.from("3000000000000000000001"))
              .add(parseEther("3000"))
          );
        expect(await contracts.vault.totalSupply()).to.eq(
          parseEther("6000").
            add(BigNumber.from("1333333333333333333333")).
            add(parseEther("2000"))
        );

        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(bob.address)))
          .to.eq(
            BigNumber.from("10928571428571428571429")
          )
        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(alice.address)))
          .to.eq(
            BigNumber.from("6071428571428571428571")
          )
      });
      it("Alice redeems 1333 shares ", async () => {
        await mintShares(alice, BigNumber.from(2000))
        await depositInVault(bob, BigNumber.from(4000))
        await simulateYield(BigNumber.from(3000));
        await depositInVault(alice, BigNumber.from(2000))
        await mintShares(bob, BigNumber.from(2000));
        await simulateYield(BigNumber.from(3000));
        expect(await contracts.vault.totalSupply()).to.eq(
          BigNumber.from("9333")
        );
        expect(await contracts.vault.expectedLiquidity()).to.eq
          (
            BigNumber.from("17001")
          );
        expect(await contracts.vault.previewRedeem(1333))
          .to.eq(
            BigNumber.from("2428")
          )
        await redeemShares(alice, BigNumber.from(1333));

        expect(await contracts.vault.expectedLiquidity()).to.eq
          (
            BigNumber.from("14573")
          );

        expect(await contracts.vault.totalAssets()).to.eq
          (
            BigNumber.from("14573")
          );
        expect(await contracts.vault.totalSupply()).to.eq(
          BigNumber.from("8000")
        );

        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(alice.address)))
          .to.eq(
            BigNumber.from("3643")
          )
        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(bob.address)))
          .to.eq(
            BigNumber.from("10929")
          )
      });
      it("Bob withdraws 2928 assets ", async () => {
        await mintShares(alice, BigNumber.from(2000))
        await depositInVault(bob, BigNumber.from(4000))
        await simulateYield(BigNumber.from(3000));
        await depositInVault(alice, BigNumber.from(2000))
        await mintShares(bob, BigNumber.from(2000));
        await simulateYield(BigNumber.from(3000));
        await redeemShares(alice, BigNumber.from(1333));
        await withdraw(bob, BigNumber.from(2928));

        expect(await contracts.vault.expectedLiquidity()).to.eq
          (
            BigNumber.from("11645")
          );

        expect(await contracts.vault.totalAssets()).to.eq
          (
            BigNumber.from("11645")
          );
        expect(await contracts.vault.totalSupply()).to.eq(
          BigNumber.from("6392")
        );

        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(alice.address)))
          .to.eq(
            BigNumber.from("3643")
          )
        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(bob.address)))
          .to.eq(
            BigNumber.from("8001")
          )
      });
      it(" Alice withdraws 3643 assets (2000 shares)  ", async () => {
        await mintShares(alice, BigNumber.from(2000))
        await depositInVault(bob, BigNumber.from(4000))
        await simulateYield(BigNumber.from(3000));
        await depositInVault(alice, BigNumber.from(2000))
        await mintShares(bob, BigNumber.from(2000));
        await simulateYield(BigNumber.from(3000));
        await redeemShares(alice, BigNumber.from(1333));
        await withdraw(bob, BigNumber.from(2928));
        expect(await withdraw(alice, BigNumber.from(3643))).to.eq(BigNumber.from("2000"));

        expect(await contracts.vault.expectedLiquidity()).to.eq
          (
            BigNumber.from("8002")
          );

        expect(await contracts.vault.totalAssets()).to.eq
          (
            BigNumber.from("8002")
          );
        expect(await contracts.vault.totalSupply()).to.eq(
          BigNumber.from("4392")
        );

        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(alice.address)))
          .to.eq(
            BigNumber.from("0")
          )
        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(bob.address)))
          .to.eq(
            BigNumber.from("8001")
          )
      });
      it("Bob redeem 4392 shares (8001 tokens)", async () => {
        await mintShares(alice, BigNumber.from(2000))
        await depositInVault(bob, BigNumber.from(4000))
        await simulateYield(BigNumber.from(3000));
        await depositInVault(alice, BigNumber.from(2000))
        await mintShares(bob, BigNumber.from(2000));
        await simulateYield(BigNumber.from(3000));
        await redeemShares(alice, BigNumber.from(1333));
        await withdraw(bob, BigNumber.from(2928));
        await withdraw(alice, BigNumber.from(3643))
        await redeemShares(bob, BigNumber.from(4392))

        expect(await contracts.vault.expectedLiquidity()).to.eq
          (
            BigNumber.from("1")
          );
        expect(await contracts.vault.totalAssets()).to.eq
          (
            BigNumber.from("1")
          );
        expect(await contracts.vault.totalSupply()).to.eq(
          BigNumber.from("0")
        );
        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(alice.address)))
          .to.eq(
            BigNumber.from("0")
          )
        expect(await contracts.vault.previewRedeem(await contracts.vault.balanceOf(bob.address)))
          .to.eq(
            BigNumber.from("0")
          )
      });
      it("Bob successfully withdraws 8001 tokens)", async () => {
        await mintShares(alice, BigNumber.from(2000))
        await depositInVault(bob, BigNumber.from(4000))
        await simulateYield(BigNumber.from(3000));
        await depositInVault(alice, BigNumber.from(2000))
        await mintShares(bob, BigNumber.from(2000));
        await simulateYield(BigNumber.from(3000));
        await redeemShares(alice, BigNumber.from(1333));
        await withdraw(bob, BigNumber.from(2928));
        await withdraw(alice, BigNumber.from(3643))
        await expect(withdraw(bob, BigNumber.from(8001))).to.not.be.reverted
      });
      it.only("Bob fails to withdraws 8002 tokens (Extra tokens))", async () => {
        await mintShares(alice, BigNumber.from(2000))
        await depositInVault(bob, BigNumber.from(4000))
        await simulateYield(BigNumber.from(3000));
        await depositInVault(alice, BigNumber.from(2000))
        await mintShares(bob, BigNumber.from(2000));
        await simulateYield(BigNumber.from(3000));
        await redeemShares(alice, BigNumber.from(1333));
        await withdraw(bob, BigNumber.from(2928));
        await withdraw(alice, BigNumber.from(3643))
        await expect(withdraw(bob, BigNumber.from(8002))).to.be.reverted
      });
    })
  })
})
