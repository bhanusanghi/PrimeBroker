/* eslint-disable no-unused-expressions */
import { expect } from "chai";
import { artifacts, ethers, network, waffle } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { mintToAccountSUSD } from "./utils/helpers";
import { metadata } from "./integrations/PerpfiOptimismMetadata";
import { erc20 } from "./integrations/addresses";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import dotenv from "dotenv";
import { SNXUNI, PERP, TRANSFERMARGIN } from "./utils/constants";
import { boolean } from "hardhat/internal/core/params/argumentTypes";

import { MarginManager, MarginAccount, RiskManager } from "../typechain-types";
dotenv.config();

// constants
const MINT_AMOUNT = ethers.BigNumber.from("1110000000000000000000000"); // == $110_000 sUSD

// synthetix (ReadProxyAddressResolver)
const ADDRESS_RESOLVER = "0x1Cb059b7e74fD21665968C908806143E744D5F30";

// synthetix: proxy
const SUSD_PROXY = "0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9";
let sUSD: Contract;

// synthetix: market keys
// see: https://github.com/Synthetixio/synthetix/blob/develop/publish/deployed/mainnet-ovm/futures-markets.json
const MARKET_KEY_sETH = ethers.utils.formatBytes32String("sETH");
const MARKET_KEY_sBTC = ethers.utils.formatBytes32String("sBTC");
const MARKET_KEY_sLINK = ethers.utils.formatBytes32String("sLINK");
const MARKET_KEY_sUNI = ethers.utils.formatBytes32String("sUNI");

// market addresses at current block
const ETH_PERP_MARKET_ADDR = "0xf86048DFf23cF130107dfB4e6386f574231a5C65";

// gelato
const GELATO_OPS = "0xB3f5503f93d5Ef84b06993a1975B9D21B962892F";

// cross margin
let marginBaseSettings: Contract;
let marginManager: Contract;
let marginAccount: Contract;
let riskManager: Contract;
let vault: Contract;
let LPToken: Contract;
let contractRegistry: Contract;
// test accounts
let account0: SignerWithAddress;
let account1: SignerWithAddress;
let perpClearingHouse: Contract;
let accountBalance: Contract;
/*///////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
///////////////////////////////////////////////////////////////*/

/**
 * @notice fork network at block number given
 */
const forkAtBlock = async (block: number) => {
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: process.env.ARCHIVE_NODE_URL_L2,
          blockNumber: block,
        },
      },
    ],
  });
};

/**
 * @notice mint sUSD to test accounts, and deploy contracts
 */
const setup = async () => {
  // get signers
  [account0, account1] = await ethers.getSigners();

  // mint account0 $100_000 sUSD
  await mintToAccountSUSD(account0.address, MINT_AMOUNT);

  // // mint account1 $100_000 sUSD
  await mintToAccountSUSD(account0.address, MINT_AMOUNT);

  // // Deploy Settings
  /**
   *  address _asset,
          address _lpTokenAddress,
          address _interestRateModelAddress,
          uint256 maxExpectedLiquidity
   */
  const contractRegistryFactory = await ethers.getContractFactory("ContractRegistry");
  contractRegistry = await contractRegistryFactory.deploy()
  const SNXRiskManager = await ethers.getContractFactory("SNXRiskManager");
  const protocolRiskManagerFactory = await ethers.getContractFactory("PerpfiRiskManager");
  const PerpfiRiskManager = await protocolRiskManagerFactory.deploy(erc20.usdc)
  const sNXRiskManager = await SNXRiskManager.deploy(erc20.sUSD)
  const _interestRateModelAddress = await ethers.getContractFactory("LinearInterestRateModel")
  const IRModel = await _interestRateModelAddress.deploy(80, 0, 4, 75);
  const _LPToken = await ethers.getContractFactory("LPToken");
  LPToken = await _LPToken.deploy("GIGABRAIN vault", "GBV", 18);
  const VaultFactory = await ethers.getContractFactory("Vault");
  const usdc = (await ethers.getContractFactory("ERC20")).attach(erc20.usdc);
  const IPerpVault = (
    await artifacts.readArtifact("contracts/Interfaces/Perpfi/IVault.sol:IVault")
  ).abi;
  const perpVault = new ethers.Contract(metadata.contracts.Vault.address, IPerpVault);
  const IClearingHouse = (
    await artifacts.readArtifact("contracts/Interfaces/Perpfi/IClearingHouse.sol:IClearingHouse")
  ).abi;
  const IAccountBalance = (
    await artifacts.readArtifact("contracts/Interfaces/Perpfi/IAccountBalance.sol:IAccountBalance")
  ).abi;
  perpClearingHouse = new ethers.Contract(metadata.contracts.ClearingHouse.address, IClearingHouse, account0);
  accountBalance = new ethers.Contract(metadata.contracts.AccountBalance.address, IAccountBalance);
  vault = await VaultFactory.deploy(erc20.usdc, LPToken.address, IRModel.address, ethers.BigNumber.from("1111111000000000000000000000000"))
  const MarginManager = await ethers.getContractFactory("MarginManager");
  marginManager = await MarginManager.deploy(contractRegistry.address)
  const RiskManager = await ethers.getContractFactory("RiskManager");
  riskManager = await RiskManager.deploy(contractRegistry.address)
  await vault.addRepayingAddress(riskManager.address)
  await vault.addlendingAddress(riskManager.address)
  // await mintToAccountSUSD(vault.address, MINT_AMOUNT);
  await riskManager.addAllowedTokens("0xD1599E478cC818AFa42A4839a6C665D9279C3E50")
  await riskManager.addAllowedTokens(erc20.usdc)
  await riskManager.setVault(vault.address)
  console.log(await riskManager.vault())
  await marginManager.SetRiskManager(riskManager.address);
  await contractRegistry.addContractToRegistry(SNXUNI, sNXRiskManager.address)
  await contractRegistry.addContractToRegistry(PERP, PerpfiRiskManager.address)
  const usdcHolder = await ethers.getImpersonatedSigner("0x625E7708f30cA75bfd92586e17077590C60eb4cD");
  const usdcHolderBalance = await usdc.balanceOf(usdcHolder.address)
  console.log(usdcHolderBalance, "yaha")
  await usdc.connect(usdcHolder).transfer(account0.address, ethers.utils.parseUnits("1", 6))
  const VAULT_AMOUNT = ethers.utils.parseUnits("1", 6)
  console.log("heh", await usdc.balanceOf(usdcHolder.address))
  await usdc.approve(perpVault.address, VAULT_AMOUNT)
  await perpVault.deposit(erc20.usdc, VAULT_AMOUNT)
};

const transferMarginData = async (address: any, amount: any) => {
  const IFuturesMarketABI = (
    await artifacts.readArtifact("contracts/Interfaces/SNX/IFuturesMarket.sol:IFuturesMarket")
  ).abi;
  const iFutures = new ethers.utils.Interface(IFuturesMarketABI)
  const data = await iFutures.encodeFunctionData("transferMargin", [amount])
  return data
}
const openPositionData = async (sizeDelta: any, trackingCode: any) => {
  const IFuturesMarketABI = (
    await artifacts.readArtifact("contracts/Interfaces/SNX/IFuturesMarket.sol:IFuturesMarket")
  ).abi;
  const iFutures = new ethers.utils.Interface(IFuturesMarketABI)
  const data = await iFutures.encodeFunctionData("modifyPositionWithTracking", [sizeDelta, trackingCode])
  return data
}
/*///////////////////////////////////////////////////////////////
                                TESTS
///////////////////////////////////////////////////////////////*/

describe("Margin Manager", () => {
  describe("Open a new account", () => {
    let accAddress: any;
    let marginAcc: any;
    // let accAddress;
    // let accAddress;
    const synthSUSDAddress = "0xD1599E478cC818AFa42A4839a6C665D9279C3E50";
    const testamt = ethers.BigNumber.from("110000000000000000000000");
    let IERC20ABI: any;
    before("Fork Network", async () => {
      await forkAtBlock(9000000);
    });
    beforeEach("Setup", async () => {
      // mint sUSD to test accounts, and deploy contracts

      IERC20ABI = (
        await artifacts.readArtifact(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
        )
      ).abi;

      await setup();
      console.log("setup done")
      sUSD = await new ethers.Contract(synthSUSDAddress, IERC20ABI, account0);
      await marginManager.openMarginAccount();
      accAddress = await marginManager.marginAccounts(account0.address)
      marginAcc = await ethers.getContractAt("MarginAccount", accAddress, account0)
      await sUSD.approve(accAddress, testamt)
      console.log("here")
      await sUSD.approve(vault.address, MINT_AMOUNT)
      await vault.deposit(MINT_AMOUNT, account0.address)

    });

    it("MarginAccount add new position using vault", async () => {

      await sUSD.approve(accAddress, ethers.BigNumber.from("10000000000000000000000"))
      await marginAcc.addCollateral(synthSUSDAddress, ethers.BigNumber.from("10000000000000000000000"))
      const myContract = await ethers.getContractAt("IAddressResolver", ADDRESS_RESOLVER);
      const fmAddress = await myContract.getAddress(ethers.utils.formatBytes32String("FuturesMarketManager"))
      const futuresManager = await ethers.getContractAt("IFuturesMarketManager", fmAddress, account0)
      const UNI_MARKET = await futuresManager.marketForKey(MARKET_KEY_sUNI)
      const trData = await transferMarginData(accAddress, ethers.BigNumber.from("28000000000000000000000"))
      const sizeDelta = ethers.BigNumber.from("28000000000000000000000");
      const posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      const uniFutures = await ethers.getContractAt("IFuturesMarket", UNI_MARKET, account0)
      const out = await marginManager.openPosition(UNI_MARKET, [SNXUNI, SNXUNI], [UNI_MARKET, UNI_MARKET], [trData, posData])
    });
  });
});
