/* eslint-disable no-unused-expressions */
import { expect } from "chai";
import { artifacts, ethers, network, waffle } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { mintToAccountSUSD } from "./utils/helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import dotenv from "dotenv";
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
// test accounts
let account0: SignerWithAddress;
let account1: SignerWithAddress;

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
  const _interestRateModelAddress = await ethers.getContractFactory("LinearInterestRateModel")
  const IRModel = await _interestRateModelAddress.deploy(80, 0, 4, 75);
  const _LPToken = await ethers.getContractFactory("LPToken");
  LPToken = await _LPToken.deploy("GIGABRAIN vault", "GBV", 18);
  const VaultFactory = await ethers.getContractFactory("Vault");
  vault = await VaultFactory.deploy("0xD1599E478cC818AFa42A4839a6C665D9279C3E50", LPToken.address, IRModel.address, ethers.BigNumber.from("1111111000000000000000000000000"))
  const MarginManager = await ethers.getContractFactory("MarginManager");
  marginManager = await MarginManager.deploy()
  const RiskManager = await ethers.getContractFactory("RiskManager");
  riskManager = await RiskManager.deploy()
  await vault.addRepayingAddress(riskManager.address)
  await vault.addlendingAddress(riskManager.address)
  // await mintToAccountSUSD(vault.address, MINT_AMOUNT);
  await riskManager.addAllowedTokens("0xD1599E478cC818AFa42A4839a6C665D9279C3E50")
  await riskManager.setVault(vault.address)
  console.log(await riskManager.vault())
  await marginManager.SetRiskManager(riskManager.address);
  // // console.log(myContract)
  // const fmAddress = await myContract.getAddress(ethers.utils.formatBytes32String("FuturesMarketManager"))
  // console.log(fmAddress)
  // const futuresManager = await ethers.getContractAt("IFuturesMarketManager", fmAddress, account0)
  // // console.log(futuresManager)
  // const out = await futuresManager.marketForKey(MARKET_KEY_sUNI)
  // // console.log(out)
  // const uniFutures = await ethers.getContractAt("IFuturesMarket", out, account0)
  // console.log(await uniFutures.marketSize())
  // const CODE = ethers.utils.formatBytes32String("GIGABRAINs")


  // "mint" accountAddress specified amount of sUSD
  // // MultiCollateralSynth contract address for sUSD
  // const synthSUSDAddress = "0xD1599E478cC818AFa42A4839a6C665D9279C3E50";
  // const ISynthABI = (
  //   await artifacts.readArtifact("contracts/Interfaces/SNX/ISynth.sol:ISynth")
  // ).abi;
  // const testamt = ethers.BigNumber.from("110000000000000000000000");
  // const synth = new ethers.Contract(synthSUSDAddress, ISynthABI, account0);
  // await synth.approve(out, testamt)
  // console.log("pre")
  // const data = await uniFutures.transferMargin(testamt)
  // console.log("pre", JSON.stringify(data))
  // console.log(await uniFutures.accessibleMargin(account0.address))
  // const out1 = await uniFutures.modifyPositionWithTracking(ethers.BigNumber.from("10000000000000000000000"), CODE);
  // console.log(await uniFutures.accessibleMargin(account0.address), "\n\n", out1)
  // console.log(await uniFutures.closePositionWithTracking(CODE))
  // console.log(await uniFutures.accessibleMargin(account0.address), "\n\n")
  // console.log(out1)
  // console.log("post")
  // marginBaseSettings = await MarginBaseSettings.deploy(
  //   KWENTA_TREASURY,
  //   tradeFee,
  //   limitOrderFee,
  //   stopLossFee
  // );

  // // Deploy Account Factory
  // const MarginAccountFactory = await ethers.getContractFactory(
  //   "MarginAccountFactory"
  // );
  // marginAccountFactory = await MarginAccountFactory.deploy(
  //   "1.0.0",
  //   SUSD_PROXY,
  //   ADDRESS_RESOLVER,
  //   marginBaseSettings.address,
  //   GELATO_OPS
  // );
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

describe("Margin Manager <> Vault", () => {
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

      sUSD = await new ethers.Contract(synthSUSDAddress, IERC20ABI, account0);
      await marginManager.openMarginAccount();
      accAddress = await marginManager.marginAccounts(account0.address)
      marginAcc = await ethers.getContractAt("MarginAccount", accAddress, account0)
      await sUSD.approve(accAddress, testamt)
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
      const out = await marginManager.addPosition(UNI_MARKET, [UNI_MARKET, UNI_MARKET], [trData, posData])
    });
  });
});
