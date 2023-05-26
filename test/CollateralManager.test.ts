/* eslint-disable no-unused-expressions */
import { expect } from "chai";
import { artifacts, ethers, network, waffle } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { ContractReceipt } from "@ethersproject/contracts"
import { mintToAccountSUSD } from "./utils/helpers";
import { mine, mineUpTo, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { metadata } from "./integrations/PerpfiOptimismMetadata";
import { erc20 } from "./integrations/addresses";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import dotenv from "dotenv";
import { SNXUNI, PERP, PERP_MARKET_KEY_AAVE, SNX_MARKET_KEY_sETH, SNX_MARKET_KEY_sUNI, TRANSFERMARGIN, ERC20 } from "./utils/constants";
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
const PERP_MARKET_KEY_UNI = ethers.utils.formatBytes32String("PERP.UNI");
const PERP_MARKET_KEY_ETH = ethers.utils.formatBytes32String("PERP.ETH");

// market addresses at current block
const ETH_PERP_MARKET_ADDR = "0xf86048DFf23cF130107dfB4e6386f574231a5C65";

// gelato
const GELATO_OPS = "0xB3f5503f93d5Ef84b06993a1975B9D21B962892F";

// cross margin
let mockAggregator: Contract;
let mockAggregatorETH: Contract;
let mockAggregatorUNI: Contract;
let mockAggregatorsUSD: Contract;
let mockAggregatorusdc: Contract;
let PriceOracle: Contract;
let exchangeRates: Contract;
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
let usdc: Contract;
let perpVault: Contract;
let MarketManager: Contract;
let UNI_MARKET: string;
let ETH_MARKET: string;
let sNXRiskManager: Contract;
let CollateralManager: Contract;
let reciept: ContractReceipt;
let _exchangeRates: string;
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
  // await mintToAccountSUSD(account0.address, MINT_AMOUNT);

  // // mint account1 $100_000 sUSD
  // await mintToAccountSUSD(account0.address, MINT_AMOUNT);

  // // Deploy Settings
  /**
   *  address _asset,
          address _lpTokenAddress,
          address _interestRateModelAddress,
          uint256 maxExpectedLiquidity
   */
  const contractRegistryFactory = await ethers.getContractFactory("ContractRegistry");
  const CollateralManagerFactory = await ethers.getContractFactory('CollateralManager');
  const aggFactory = await ethers.getContractFactory('MockAggregatorV2V3')
  mockAggregator = await aggFactory.deploy()
  await mockAggregator.setDecimals(18);
  CollateralManager = await CollateralManagerFactory.deploy()
  const MarketManagerFactory = await ethers.getContractFactory("MarketManager");
  MarketManager = await MarketManagerFactory.deploy()
  contractRegistry = await contractRegistryFactory.deploy()
  const SNXRiskManager = await ethers.getContractFactory("SNXRiskManager");
  const protocolRiskManagerFactory = await ethers.getContractFactory("PerpfiRiskManager");
  const PerpfiRiskManager = await protocolRiskManagerFactory.deploy(erc20.usdc, metadata.contracts.AccountBalance.address, metadata.contracts.Exchange.address, metadata.contracts.MarketRegistry.address)
  sNXRiskManager = await SNXRiskManager.deploy(erc20.sUSD)
  const _interestRateModelAddress = await ethers.getContractFactory("LinearInterestRateModel")
  const IRModel = await _interestRateModelAddress.deploy(80, 0, 4, 75);
  const _LPToken = await ethers.getContractFactory("LPToken");
  LPToken = await _LPToken.deploy("GIGABRAIN vault", "GBV", 18);
  const VaultFactory = await ethers.getContractFactory("Vault");
  usdc = (await ethers.getContractFactory("ERC20")).attach(erc20.usdc);
  const IPerpVault = (
    await artifacts.readArtifact("contracts/Interfaces/Perpfi/IVault.sol:IVault")
  ).abi;
  perpVault = new ethers.Contract(metadata.contracts.Vault.address, IPerpVault, account0);
  const IClearingHouse = (
    await artifacts.readArtifact("contracts/Interfaces/Perpfi/IClearingHouse.sol:IClearingHouse")
  ).abi;
  const IAccountBalance = (
    await artifacts.readArtifact("contracts/Interfaces/Perpfi/IAccountBalance.sol:IAccountBalance")
  ).abi;
  perpClearingHouse = new ethers.Contract(metadata.contracts.ClearingHouse.address, IClearingHouse, account0);
  accountBalance = new ethers.Contract(metadata.contracts.AccountBalance.address, IAccountBalance);
  const vault_deployed = await VaultFactory.deploy(erc20.usdc, "Giga lp", "GLP", IRModel.address, ethers.BigNumber.from("1111111000000000000000000000000"))
  const VAULT_ABI = (
    await artifacts.readArtifact("contracts/MarginPool/Vault.sol:Vault")
  ).abi;
  vault = new ethers.Contract(vault_deployed.address, VAULT_ABI, account0)
  const oracleFactory = await ethers.getContractFactory("PriceOracle");
  PriceOracle = await oracleFactory.deploy()
  const MarginManager = await ethers.getContractFactory("MarginManager");
  marginManager = await MarginManager.deploy(contractRegistry.address, MarketManager.address, PriceOracle.address)
  const RiskManager = await ethers.getContractFactory("RiskManager");
  riskManager = await RiskManager.deploy(contractRegistry.address, MarketManager.address)
  await vault.addLendingAddress(riskManager.address)
  await vault.addRepayingAddress(riskManager.address)
  await vault.addLendingAddress(marginManager.address)
  await vault.addRepayingAddress(marginManager.address)
  // await mintToAccountSUSD(vault.address, MINT_AMOUNT);
  await CollateralManager.addAllowedCollateral([erc20.usdc, erc20.sUSD], [100, 100])
  await CollateralManager.initialize(marginManager.address, riskManager.address, PriceOracle.address)//@notice dummy address
  await riskManager.setVault(vault.address)
  await marginManager.setVault(vault.address)
  await marginManager.SetRiskManager(riskManager.address);
  await contractRegistry.addContractToRegistry(SNXUNI, sNXRiskManager.address)
  await contractRegistry.addContractToRegistry(PERP, PerpfiRiskManager.address)
  // await MarketManager.addMarket([sNXRiskManager.address, PerpfiRiskManager.address])
  const IERC20ABI = (
    await artifacts.readArtifact(
      "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
    )
  ).abi;
  const usdcHolder = await ethers.getImpersonatedSigner("0x7F5c764cBc14f9669B88837ca1490cCa17c31607");
  const usdcHolderBalance = await usdc.balanceOf(usdcHolder.address)

  await usdc.connect(usdcHolder).transfer(account0.address, usdcHolderBalance)
  const VAULT_AMOUNT = ethers.utils.parseUnits("20000", 6)
  await usdc.connect(account0).approve(vault.address, VAULT_AMOUNT)
  await vault.deposit(VAULT_AMOUNT, account0.address)
  const perpVaultAmount = ethers.utils.parseUnits("2000", 6)
  await riskManager.setcollateralManager(CollateralManager.address)
  await usdc.approve(perpVault.address, perpVaultAmount)

  await perpVault.deposit(erc20.usdc, perpVaultAmount)
  await MarketManager.addMarket(PERP_MARKET_KEY_AAVE, metadata.contracts.ClearingHouse.address, PerpfiRiskManager.address)
  mockAggregatorETH = await aggFactory.deploy()
  await mockAggregatorETH.setDecimals(18);
  mockAggregatorusdc = await aggFactory.deploy()
  await mockAggregatorusdc.setDecimals(6);
  mockAggregatorsUSD = await aggFactory.deploy()
  await mockAggregatorsUSD.setDecimals(18);
  mockAggregatorUNI = await aggFactory.deploy()
  await mockAggregatorUNI.setDecimals(18);
  await PriceOracle.addPriceFeed(erc20.sUSD, mockAggregatorsUSD.address)
  let { timestamp } = await ethers.provider.getBlock("latest");
  await mockAggregatorsUSD.setLatestAnswer(ethers.utils.parseUnits("1", 18), timestamp)
  await mockAggregatorusdc.setLatestAnswer(ethers.utils.parseUnits("1", 6), timestamp)
  await PriceOracle.addPriceFeed(erc20.usdc, mockAggregatorusdc.address)
};
/*///////////////////////////////////////////////////////////////
                                TESTS
///////////////////////////////////////////////////////////////*/

describe("CollateralManager", () => {
  describe("CM:", () => {
    let accAddress: any;
    let marginAccount: any;
    let depositAmount: any;
    beforeEach("Setup", async () => {
      await forkAtBlock(37274241);
      await setup();
      console.log("setup done")
      const IERC20ABI = (
        await artifacts.readArtifact(
          "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
        )
      ).abi;
      sUSD = await new ethers.Contract(erc20.sUSD, IERC20ABI, account0);
      await marginManager.openMarginAccount();
      accAddress = await marginManager.marginAccounts(account0.address)
      marginAccount = await ethers.getContractAt("MarginAccount", accAddress, account0)
      const myContract = await ethers.getContractAt("IAddressResolver", ADDRESS_RESOLVER);
      _exchangeRates = await myContract.getAddress(ethers.utils.formatBytes32String("ExchangeRates"))
      const fmAddress = await myContract.getAddress(ethers.utils.formatBytes32String("FuturesMarketManager"))
      const futuresManager = await ethers.getContractAt("IFuturesMarketManager", fmAddress, account0)
      UNI_MARKET = await futuresManager.marketForKey(MARKET_KEY_sUNI)
      ETH_MARKET = await futuresManager.marketForKey(MARKET_KEY_sETH)

      console.log(ETH_MARKET, "FM address", futuresManager.address)
      const uniFutures = await ethers.getContractAt("IFuturesMarket", UNI_MARKET, account0)

      await sNXRiskManager.addNewMarket(UNI_MARKET)
      await sNXRiskManager.addNewMarket(ETH_MARKET)
      await MarketManager.addMarket(SNX_MARKET_KEY_sUNI, UNI_MARKET, sNXRiskManager.address)
      await MarketManager.addMarket(SNX_MARKET_KEY_sETH, ETH_MARKET, sNXRiskManager.address)

      depositAmount = ethers.utils.parseUnits("6500", 6)
      await usdc.approve(accAddress, depositAmount)
      await CollateralManager.addCollateral(usdc.address, depositAmount)
    });
    it("Test deposit collateral", async () => {
      expect(await CollateralManager.totalCollateralValue(accAddress)).to.eq(depositAmount);
    });
    it("Test withdraw collateral", async () => {
      await CollateralManager.withdrawCollateral(usdc.address, depositAmount)
      expect(await CollateralManager.totalCollateralValue(accAddress)).to.eq(ethers.BigNumber.from('0'));
    });
    it("Test collateral weight and withdraw", async () => {
      const newWeight = 85
      await CollateralManager.updateCollateralWeight(erc20.usdc, newWeight)
      expect(await CollateralManager.totalCollateralValue(accAddress)).to.eq(depositAmount.mul(newWeight).div(100));
      await CollateralManager.withdrawCollateral(usdc.address, depositAmount)
      expect(await CollateralManager.totalCollateralValue(accAddress)).to.eq(ethers.BigNumber.from('0'));
    });
    it("Test collateral weight and price change, withdraw", async () => {
      const newWeight = 90
      const newPrice = 1.5
      await CollateralManager.updateCollateralWeight(erc20.usdc, newWeight)
      expect(await CollateralManager.totalCollateralValue(accAddress)).to.eq(depositAmount.mul(newWeight).div(100));
      let { timestamp } = await ethers.provider.getBlock("latest");
      await mockAggregatorusdc.setLatestAnswer(ethers.utils.parseUnits(newPrice.toString(), 6), timestamp)
      expect(await CollateralManager.totalCollateralValue(accAddress)).to.eq(depositAmount.mul(newWeight * newPrice).div(100));
      await CollateralManager.withdrawCollateral(usdc.address, depositAmount)
      expect(await CollateralManager.totalCollateralValue(accAddress)).to.eq(ethers.BigNumber.from('0'));
    });
  });
});

