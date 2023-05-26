/* eslint-disable no-unused-expressions */
import { expect } from "chai";
import { artifacts, ethers, network, waffle } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { mintToAccountSUSD } from "./utils/helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import dotenv from "dotenv";
import { boolean } from "hardhat/internal/core/params/argumentTypes";
import { SNXUNI, TRANSFERMARGIN, SNX_MARKET_KEY_sUNI } from "./utils/constants";
import { MarginManager, MarginAccount, RiskManager } from "../typechain-types";
import { transferMarginDataSNX, openPositionDataSNX } from "./utils/CalldataGenerator"
import { erc20 } from "./integrations/addresses";
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
let MarketManager: Contract;
let sNXRiskManager: Contract;
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
  const contractRegistryFactory = await ethers.getContractFactory("ContractRegistry");
  contractRegistry = await contractRegistryFactory.deploy()
  const MarketManagerFactory = await ethers.getContractFactory("MarketManager");
  MarketManager = await MarketManagerFactory.deploy()
  contractRegistry = await contractRegistryFactory.deploy()
  const _interestRateModelAddress = await ethers.getContractFactory("LinearInterestRateModel")
  const IRModel = await _interestRateModelAddress.deploy(80, 0, 4, 75);
  const _LPToken = await ethers.getContractFactory("LPToken");
  LPToken = await _LPToken.deploy("GIGABRAIN vault", "GBV", 18);
  const VaultFactory = await ethers.getContractFactory("Vault");
  const RiskManager = await ethers.getContractFactory("RiskManager");
  riskManager = await RiskManager.deploy(contractRegistry.address, MarketManager.address)
  vault = await VaultFactory.deploy(erc20.sUSD, LPToken.address, IRModel.address, ethers.BigNumber.from("1111111000000000000000000000000"))
  const MarginManager = await ethers.getContractFactory("MarginManager");
  marginManager = await MarginManager.deploy(contractRegistry.address, MarketManager.address)
  const SNXRiskManager = await ethers.getContractFactory("SNXRiskManager");
  sNXRiskManager = await SNXRiskManager.deploy(erc20.sUSD)
  // await mintToAccountSUSD(vault.address, MINT_AMOUNT);
  await riskManager.addAllowedTokens(erc20.sUSD)
  await riskManager.setVault(vault.address)

  await vault.addRepayingAddress(riskManager.address)
  await vault.addlendingAddress(riskManager.address)
  await contractRegistry.addContractToRegistry(SNXUNI, sNXRiskManager.address)
  await marginManager.SetRiskManager(riskManager.address);
};

/*///////////////////////////////////////////////////////////////
                                TESTS
///////////////////////////////////////////////////////////////*/

describe("Margin Manager:SNX", () => {
  describe("Open a new account", () => {
    let accAddress: any;
    let marginAccount: any;
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

      sUSD = await new ethers.Contract(erc20.sUSD, IERC20ABI, account0);
      const myContract = await ethers.getContractAt("IAddressResolver", ADDRESS_RESOLVER);
      const fmAddress = await myContract.getAddress(ethers.utils.formatBytes32String("FuturesMarketManager"))
      const futuresManager = await ethers.getContractAt("IFuturesMarketManager", fmAddress, account0)
      const UNI_MARKET = await futuresManager.marketForKey(MARKET_KEY_sUNI)
      const ETH_MARKET = await futuresManager.marketForKey(MARKET_KEY_sETH)
      await riskManager.addNewMarket(SNX_MARKET_KEY_sUNI, UNI_MARKET)
      await MarketManager.addMarket(SNX_MARKET_KEY_sUNI, UNI_MARKET, sNXRiskManager.address)
      await marginManager.openMarginAccount();
      accAddress = await marginManager.marginAccounts(account0.address)
      marginAccount = await ethers.getContractAt("MarginAccount", accAddress, account0)
      await sUSD.approve(accAddress, testamt)
      await sUSD.approve(vault.address, MINT_AMOUNT)
      await vault.deposit(MINT_AMOUNT, account0.address)

    });

    it("Margin manager.open new account", async () => {
      await marginAccount.addCollateral(synthSUSDAddress, testamt)
      let balance = await sUSD.balanceOf(accAddress);
      expect(balance).to.equal(testamt);
    });

    it("MarginAccount add new position", async () => {
      await sUSD.approve(accAddress, testamt)
      await marginAccount.addCollateral(synthSUSDAddress, testamt)
      const myContract = await ethers.getContractAt("IAddressResolver", ADDRESS_RESOLVER);
      const fmAddress = await myContract.getAddress(ethers.utils.formatBytes32String("FuturesMarketManager"))
      const futuresManager = await ethers.getContractAt("IFuturesMarketManager", fmAddress, account0)
      const UNI_MARKET = await futuresManager.marketForKey(MARKET_KEY_sUNI)
      const trData = await transferMarginDataSNX(accAddress, testamt)
      const sizeDelta = ethers.BigNumber.from("10000000000000000000000");
      const posData = await openPositionDataSNX(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      const uniFutures = await ethers.getContractAt("IFuturesMarket", UNI_MARKET, account0)

      const out = await marginManager.openPosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET, UNI_MARKET], [trData, posData])
    });
    it("MarginAccount close position", async () => {
      await sUSD.approve(accAddress, testamt)
      await marginAccount.addCollateral(synthSUSDAddress, testamt)
      const myContract = await ethers.getContractAt("IAddressResolver", ADDRESS_RESOLVER);

      const fmAddress = await myContract.getAddress(ethers.utils.formatBytes32String("FuturesMarketManager"))
      const futuresManager = await ethers.getContractAt("IFuturesMarketManager", fmAddress, account0)
      const UNI_MARKET = await futuresManager.marketForKey(MARKET_KEY_sUNI)
      const trData = await transferMarginDataSNX(accAddress, testamt)
      let sizeDelta = ethers.BigNumber.from("10000000000000000000000");
      const posData = await openPositionDataSNX(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      await marginManager.openPosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET, UNI_MARKET], [trData, posData])
      const uniFutures = await ethers.getContractAt("IFuturesMarket", UNI_MARKET, account0)
      let Position = await uniFutures.positions(accAddress)
      expect(Position.size).to.equal(sizeDelta);
      sizeDelta = sizeDelta.mul(-1);
      const posData2 = await openPositionDataSNX(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      const out = await marginManager.closePosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET], [posData2])
      Position = await uniFutures.positions(accAddress);
      expect(Position.size).to.equal(BigNumber.from('0'));
    });
    it("MarginAccount add position by 50% and close 50% of it", async () => {
      await sUSD.approve(accAddress, testamt)
      await marginAccount.addCollateral(synthSUSDAddress, testamt)
      const myContract = await ethers.getContractAt("IAddressResolver", ADDRESS_RESOLVER);
      const fmAddress = await myContract.getAddress(ethers.utils.formatBytes32String("FuturesMarketManager"))
      const futuresManager = await ethers.getContractAt("IFuturesMarketManager", fmAddress, account0)
      const UNI_MARKET = await futuresManager.marketForKey(MARKET_KEY_sUNI)
      const trData = await transferMarginDataSNX(accAddress, testamt)
      let sizeDelta = ethers.BigNumber.from("10000000000000000000000");
      const posData = await openPositionDataSNX(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      await marginManager.openPosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET, UNI_MARKET], [trData, posData])
      const uniFutures = await ethers.getContractAt("IFuturesMarket", UNI_MARKET, account0)
      let Position = await uniFutures.positions(accAddress)
      expect(Position.size).to.equal(sizeDelta);
      const posData2 = await openPositionDataSNX(sizeDelta.div(2), ethers.utils.formatBytes32String("GIGABRAINs"))
      await marginManager.updatePosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET], [posData2])

      Position = await uniFutures.positions(accAddress);
      expect(Position.size).to.equal(sizeDelta.add(sizeDelta.div(2)));
      const posData3 = await openPositionDataSNX(sizeDelta.div(2).mul(-1), ethers.utils.formatBytes32String("GIGABRAINs"))
      await marginManager.updatePosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET], [posData3])
      Position = await uniFutures.positions(accAddress);
      expect(Position.size).to.equal(sizeDelta);
      await marginManager.closePosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET], [await openPositionDataSNX(sizeDelta.mul(-1), ethers.utils.formatBytes32String("GIGABRAINs"))])
      Position = await uniFutures.positions(accAddress);
      expect(Position.size).to.equal(BigNumber.from('0'));
    });

    it("MarginAccount take a short", async () => {
      await sUSD.approve(accAddress, testamt)
      await marginAccount.addCollateral(synthSUSDAddress, testamt)
      const myContract = await ethers.getContractAt("IAddressResolver", ADDRESS_RESOLVER);
      const fmAddress = await myContract.getAddress(ethers.utils.formatBytes32String("FuturesMarketManager"))
      const futuresManager = await ethers.getContractAt("IFuturesMarketManager", fmAddress, account0)
      const UNI_MARKET = await futuresManager.marketForKey(MARKET_KEY_sUNI)
      const trData = await transferMarginDataSNX(accAddress, testamt)
      let sizeDelta = ethers.BigNumber.from("10000000000000000000000");
      const posData1 = await openPositionDataSNX(sizeDelta.mul(-1), ethers.utils.formatBytes32String("GIGABRAINs"))
      await marginManager.openPosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET, UNI_MARKET], [trData, posData1])
      const uniFutures = await ethers.getContractAt("IFuturesMarket", UNI_MARKET, account0)
      let Position = await uniFutures.positions(accAddress)
      expect(Position.size).to.equal(sizeDelta.mul(-1));
      const posData2 = await openPositionDataSNX(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      await marginManager.closePosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET], [posData2])
      Position = await uniFutures.positions(accAddress)
      expect(Position.size).to.equal(BigNumber.from('0'));
    });
  });
});
