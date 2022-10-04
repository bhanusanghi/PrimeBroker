import { expect } from "chai"
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
import { ethers, network } from "hardhat";
import { BigNumber } from "ethers";
import { erc20 } from "./integrations/addresses";
import { MarginManager, MarginAccount, ERC20 } from "../typechain-types";
import { metadata } from "./integrations/PerpfiOptimismMetadata";
import { abi as perpVaultAbi } from "./external/abi/perpVault";
import { abi as perpClearingHouseAbi } from "./external/abi/clearingHouse";
import { abi as perpAccountBalanceAbi } from "./external/abi/accountBalance";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { resetFork } from "./utils/helpers";
import { getVaultDepositCalldata, getErc20ApprovalCalldata } from "./utils/CalldataGenerator";
import { PERP, ERC20 as ERC20Hash } from "./utils/constants";

const ETHER = 10 ** 18
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
let admin: SignerWithAddress, bob: SignerWithAddress;
const fraxMetadata = metadata.collaterals[1];

enum txMetaType {
  ERC20_APPROVAL,
  ERC20_TRANSFER,
  EXTERNAL_PROTOCOL
}

async function initializeContractsFixture(): Promise<Contracts> {
  // init contracts registry
  const contractRegistryFactory = await ethers.getContractFactory("ContractRegistry");
  const contractRegistry = await contractRegistryFactory.deploy()

  // init Risk manager
  const riskManagerFactory = await ethers.getContractFactory("RiskManager");
  const riskManager = await riskManagerFactory.deploy(contractRegistry.address)

  const protocolRiskManagerFactory = await ethers.getContractFactory("PerpfiRiskManager");
  const PerpfiRiskManager = await protocolRiskManagerFactory.deploy()

  // Add to contract registry
  await contractRegistry.addContractToRegistry(PERP, PerpfiRiskManager.address)
  // init margin manager
  const marginManagerFactory = await ethers.getContractFactory("MarginManager");
  const marginManager = await marginManagerFactory.deploy(contractRegistry.address);
  await marginManager.toggleAllowedUnderlyingToken(erc20.usdc);
  await marginManager.SetRiskManager(riskManager.address);

  (await marginManager.connect(bob).openMarginAccount(erc20.usdc)) as any as string;
  const marginAccountAddress: string = await marginManager.marginAccounts(bob.address)
  const marginAccount: MarginAccount = await (await ethers.getContractFactory("MarginAccount")).attach(marginAccountAddress) as MarginAccount

  const usdc = (await ethers.getContractFactory("ERC20")).attach(erc20.usdc);
  const frax = (await ethers.getContractFactory("ERC20")).attach(fraxMetadata.address);
  const perpVault = new ethers.Contract(metadata.contracts.Vault.address, perpVaultAbi);
  const perpClearingHouse = new ethers.Contract(metadata.contracts.ClearingHouse.address, perpClearingHouseAbi);
  const accountBalance = new ethers.Contract(metadata.contracts.AccountBalance.address, perpAccountBalanceAbi);
  // return all

  return {
    marginAccount,
    marginManager,
    erc20: {
      usdc, frax
    },
    perp: {
      vault: perpVault,
      clearingHouse: perpClearingHouse,
      accountBalance
    }
  };
}

const fundPerpVault = async (account: SignerWithAddress, amount: BigNumber) => {
  await contracts.erc20.usdc.connect(account).approve(contracts.perp.vault.address, amount)
  await contracts.perp.vault.connect(account).deposit(contracts.erc20.usdc.address, amount)
}

describe("MarginManager", () => {
  beforeEach(async () => {
    // await resetFork();
    [admin, bob] = await ethers.getSigners()
    contracts = await initializeContractsFixture();
    // contracts = await loadFixture(initializeContractsFixture);
    // account with usdc - 0xebe80f029b1c02862b9e8a70a7e5317c06f62cae
    const usdcHolder = await ethers.getImpersonatedSigner("0xebe80f029b1c02862b9e8a70a7e5317c06f62cae");
    // const fraxHolder = await ethers.getImpersonatedSigner("0x29a3d66b30bc4ad674a4fdaf27578b64f6afbfe7");
    // send usdc
    const usdcHolderBalance = await contracts.erc20.usdc.balanceOf(usdcHolder.address)
    await contracts.erc20.usdc.connect(usdcHolder).transfer(bob.address, ethers.utils.parseUnits("100000", 6))
    // send frax
    // contracts.erc20.frax.connect(fraxHolder).transfer(bob.address, 10000 * ETHER)

    // put some money in margin account.
    // await contracts.marginAccount.connect(bob).addCollateral(2000 * ETHER)
  })
  describe("Fork test", () => {
    it("should allow Bob to fund PerpFi Vault directly", async () => {
      const parsedAmount = ethers.utils.parseUnits("1000", 6)
      await fundPerpVault(bob, parsedAmount)
      await expect(await contracts.perp.vault.connect(bob).getBalance(bob.address)).to.eq(parsedAmount);
    })
    // if trader is on long side, baseToQuote: true, exactInput: true
    // if trader is on short side, baseToQuote: false (quoteToBase), exactInput: false (exactOutput)
    it.only("should allow opening a long position on perp directly", async () => {

      const baseToken = "0x34235C8489b06482A99bb7fcaB6d7c467b92d248";
      const parsedAmount = ethers.utils.parseUnits("10000", 6)
      await fundPerpVault(bob, parsedAmount.mul(BigNumber.from(`10`)));
      const openPositionParams = {
        baseToken,
        isBaseToQuote: false,// long vAave
        isExactInput: true,
        // amount: ethers.utils.parseEther("100"),
        amount: ethers.utils.parseUnits("1000", 6),
        oppositeAmountBound: 0,
        deadline: ethers.constants.MaxUint256,
        sqrtPriceLimitX96: 0, // price slippage protection
        referralCode: ethers.constants.HashZero,
      }
      // make static call to check return value
      // const staticResponse = await contracts.perp.clearingHouse.connect(bob).callStatic.openPosition(openPositionParams);

      // const expectedBase = staticResponse.base;
      // expect(staticResponse.quote).to.be.eq(ethers.utils.parseUnits("1000", 6));
      // console.log("Finished static call, expectedBase - ", expectedBase.toString());


      // await contracts.perp.clearingHouse.connect(bob).openPosition(openPositionParams)
      // ).to.emit(contracts.perp.clearingHouse, "PositionChanged")
      // .withArgs(
      //   bob.address, // trader
      //   baseToken, // baseToken
      //   "6539527905092835", // exchangedPositionSize
      //   parseEther("-0.99"), // exchangedPositionNotional
      //   parseEther("0.01"), // fee = 1 * 0.01
      //   parseEther("-1"), // openNotional
      //   parseEther("0"), // realizedPnl
      //   "974863323923301853330898562804", // sqrtPriceAfterX96
      // );
      console.log("fetching accBalance");
      console.log(bob.address)
      console.log(baseToken)
      // console.log(contracts.perp.accountBalance)
      let accBalance = await contracts.perp.accountBalance.getAccountInfo(bob.address, baseToken);
      console.log("accBalance");
      console.log(accBalance);

      // const [baseBalance, quoteBalance] = await contracts.perp.clearingHouse.getTokenBalance(
      //   bob.address,
      //   baseToken,
      // )
      // console.log("baseBalance", baseBalance)
      // console.log("quoteBalance", quoteBalance)
    });
    // it.only("should allow opening a long position on perp directly", async () => {
    //   const parsedAmount = ethers.utils.parseUnits("10000", 6)
    //   await fundPerpVault(bob, parsedAmount);
    //   const openPositionParams = {
    //     baseToken: "0x34235C8489b06482A99bb7fcaB6d7c467b92d248",
    //     isBaseToQuote: false,// long vAave
    //     isExactInput: true,
    //     // amount: ethers.utils.parseEther("100"),
    //     amount: parsedAmount,
    //     oppositeAmountBound: 0,
    //     deadline: ethers.constants.MaxUint256,
    //     sqrtPriceLimitX96: 0, // price slippage protection
    //     referralCode: ethers.constants.HashZero,
    //   }
    //   const response = await contracts.perp.clearingHouse.connect(bob).openPosition(openPositionParams);

    //   const accountData = await contracts.perp.accountBalance.getAccountInfo(bob.address, "0x34235C8489b06482A99bb7fcaB6d7c467b92d248");
    //   console.log("Account data", accountData)
    // });

    it("should allow funding vault using margin account.", async () => {
      const parsedAmount = ethers.utils.parseUnits("10000", 6)

      // bob funds CreditAccount with usdc.
      await contracts.erc20.usdc.connect(bob).transfer(contracts.marginAccount.address, parsedAmount)

      // fundCreditAccount with vAave for now.

      const approveAmountCalldata = await getErc20ApprovalCalldata(contracts.perp.vault.address, parsedAmount);
      console.log("approveAmountCalldata - ", approveAmountCalldata);

      const fundVaultCalldata = await getVaultDepositCalldata(erc20.usdc, parsedAmount);
      console.log("fundVaultCalldata - ", fundVaultCalldata);

      // console.log(
      //   [ERC20Hash, PERP],
      //   [BigNumber.from(0), BigNumber.from(2)],
      //   // [txMetaType.ERC20_APPROVAL, txMetaType.EXTERNAL_PROTOCOL,],
      //   [erc20.usdc, contracts.perp.vault.address],
      //   [approveAmountCalldata, fundVaultCalldata]
      // )

      const response = await contracts.marginManager.connect(bob).addPosition(
        [ERC20Hash, PERP],
        [txMetaType.ERC20_APPROVAL, txMetaType.EXTERNAL_PROTOCOL,],
        [erc20.usdc, contracts.perp.vault.address],
        [approveAmountCalldata, fundVaultCalldata]
      );
    });
  });

  // bytes32[] memory contractName,
  // txMetadata[] memory transactionMetadata,
  // address[] memory contractAddress,
  // bytes[] memory data

})