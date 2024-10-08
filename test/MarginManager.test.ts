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
import { boolean } from "hardhat/internal/core/params/argumentTypes";
import { perpOpenPositionCallData, getVaultDepositCalldata, getErc20ApprovalCalldata, getClosePerpPositionCalldata, getVaultWithdrawCalldata } from "./utils/CalldataGenerator";
import { MarginManager, MarginAccount, RiskManager, ChainlinkPriceFeedV2 } from "../typechain-types";
// import { ChainlinkPriceFeedV2 } from "../typechain/perp-oracle"
import { time } from "console";
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

  const MarketManagerFactory = await ethers.getContractFactory("MarketManager");
  MarketManager = await MarketManagerFactory.deploy()
  contractRegistry = await contractRegistryFactory.deploy()
  const SNXRiskManager = await ethers.getContractFactory("SNXRiskManager");
  const protocolRiskManagerFactory = await ethers.getContractFactory("PerpfiRiskManager");
  const PerpfiRiskManager = await protocolRiskManagerFactory.deploy(erc20.usdc, metadata.contracts.AccountBalance.address, metadata.contracts.Exchange.address, metadata.contracts.MarketRegistry.address, metadata.contracts.ClearingHouse.address)
  sNXRiskManager = await SNXRiskManager.deploy(erc20.sUSD, contractRegistry.address)
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

  CollateralManager = await CollateralManagerFactory.deploy(marginManager.address, riskManager.address, PriceOracle.address)
  // await CollateralManager.addAllowedCollateral([erc20.usdc, erc20.sUSD], [100, 100])
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
  // const sUsdHolder = await ethers.getImpersonatedSigner("0xa5f7a39e55d7878bc5bd754ee5d6bd7a7662355b");
  const usdcHolderBalance = await usdc.balanceOf(usdcHolder.address)
  console.log('max usdc balance', usdcHolderBalance)
  // sUSD = (await ethers.getContractFactory("ERC20")).attach(erc20.sUSD);
  // const susdHolderBalance = await sUSD.balanceOf(sUsdHolder.address)

  await usdc.connect(usdcHolder).transfer(account0.address, usdcHolderBalance)
  // await sUSD.connect(sUsdHolder).transfer(account0.address, susdHolderBalance)
  // sUSD = new ethers.Contract("0xD1599E478cC818AFa42A4839a6C665D9279C3E50", IERC20ABI, account0);
  const VAULT_AMOUNT = ethers.utils.parseUnits("20000", 6)
  await usdc.connect(account0).approve(vault.address, VAULT_AMOUNT)
  await vault.deposit(VAULT_AMOUNT, account0.address)
  const perpVaultAmount = ethers.utils.parseUnits("2000", 6)
  await riskManager.setCollateralManager(CollateralManager.address)
  await usdc.approve(perpVault.address, perpVaultAmount)

  // await perpVault.deposit(erc20.usdc, perpVaultAmount)
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
    let marginAccount: any;
    // let accAddress;
    // let accAddress;
    const testamt = ethers.utils.parseUnits("1000", 18);
    let IERC20ABI: any;
    beforeEach("Setup", async () => {
      // mint sUSD to test accounts, and deploy contracts
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
      const fmAddress = await myContract.getAddress(ethers.utils.formatBytes32String("FuturesMarketManager"))
      const futuresManager = await ethers.getContractAt("IFuturesMarketManager", fmAddress, account0)
      UNI_MARKET = await futuresManager.marketForKey(MARKET_KEY_sUNI)

      const uniFutures = await ethers.getContractAt("IFuturesMarket", UNI_MARKET, account0)
      await MarketManager.addMarket(SNX_MARKET_KEY_sUNI, UNI_MARKET, sNXRiskManager.address)
      await sNXRiskManager.addNewMarket(UNI_MARKET)
      await sNXRiskManager.addNewMarket(ETH_MARKET)
      await MarketManager.addMarket(SNX_MARKET_KEY_sUNI, UNI_MARKET, sNXRiskManager.address)
      await MarketManager.addMarket(SNX_MARKET_KEY_sETH, ETH_MARKET, sNXRiskManager.address)

      // await riskManager.addNewMarket(SNX_MARKET_KEY_sUNI, UNI_MARKET)
      // await riskManager.addNewMarket(SNX_MARKET_KEY_sETH, ETH_MARKET)
      // await riskManager.addNewMarket(PERP_MARKET_KEY_AAVE, metadata.contracts.ClearingHouse.address)
      // await usdc.transfer(accAddress, ethers.utils.parseUnits("10000", 6))

      // await sUSD.approve(accAddress, ethers.utils.parseUnits("5000", 6))
      // await marginAccount.addCollateral(usdc.address, ethers.utils.parseUnits("5000", 6))
    });
    // it("test swap"), async () => {
    //   const out = marginAccount.swap()
    // }
    it("MarginAccount add new position using vault", async () => {

      await usdc.approve(accAddress, ethers.utils.parseUnits("5000", 6))
      await CollateralManager.addCollateral(usdc.address, ethers.utils.parseUnits("5000", 6))


      const trData = await transferMarginData(accAddress, ethers.utils.parseUnits("1000", 18))
      const sizeDelta = ethers.utils.parseUnits("50", 18);
      const posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      // const uniFutures = await ethers.getContractAt("IFuturesMarket", UNI_MARKET, account0)

      const out = await marginManager.openPosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET, UNI_MARKET], [trData, posData])
      const parsedAmount = ethers.utils.parseUnits("1000", 6)
      await usdc.transfer(marginAccount.address, parsedAmount)

      // fundCreditAccount with vAave for now.

      const approveAmountCalldata = await getErc20ApprovalCalldata(perpVault.address, parsedAmount);
      console.log("approveAmountCalldata - ", approveAmountCalldata);

      const fundVaultCalldata = await getVaultDepositCalldata(erc20.usdc, parsedAmount);
      console.log("fundVaultCalldata - ", fundVaultCalldata);
      const _perpOpenPositionCallData = await perpOpenPositionCallData(
        "0x34235C8489b06482A99bb7fcaB6d7c467b92d248",
        false,
        true,
        ethers.BigNumber.from('0'),
        ethers.BigNumber.from(parsedAmount),
        ethers.BigNumber.from('0'),
        ethers.constants.MaxUint256,
        ethers.constants.HashZero)

      console.log("perpOpenPositionCallData - ", _perpOpenPositionCallData)
      const response = await marginManager.openPosition(
        PERP_MARKET_KEY_AAVE,
        [erc20.usdc, perpVault.address, perpClearingHouse.address],
        [approveAmountCalldata, fundVaultCalldata, _perpOpenPositionCallData]
      );

      console.log(await marginAccount.positions(PERP_MARKET_KEY_AAVE), await marginAccount.positions(SNX_MARKET_KEY_sUNI))
    });
  });
  describe("Margin Manager:max leverage", () => {
    let accAddress: any;
    let marginAccount: any;
    const testamt = ethers.utils.parseUnits("1000", 18);
    let IERC20ABI: any;
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

      // await sNXRiskManager.addNewMarket(UNI_MARKET)
      // await sNXRiskManager.addNewMarket(ETH_MARKET)
      // await MarketManager.addMarket(SNX_MARKET_KEY_sUNI, UNI_MARKET, sNXRiskManager.address)
      // await MarketManager.addMarket(SNX_MARKET_KEY_sETH, ETH_MARKET, sNXRiskManager.address)

      // await riskManager.addNewMarket(SNX_MARKET_KEY_sUNI, UNI_MARKET)
      // await riskManager.addNewMarket(SNX_MARKET_KEY_sETH, ETH_MARKET)
      // await riskManager.addNewMarket(PERP_MARKET_KEY_AAVE, metadata.contracts.ClearingHouse.address)
    });
    it("MarginAccount add/update position", async () => {

      await usdc.approve(accAddress, ethers.utils.parseUnits("5000", 6))
      await CollateralManager.addCollateral(usdc.address, ethers.utils.parseUnits("5000", 6))


      let trData = await transferMarginData(accAddress, ethers.utils.parseUnits("1000", 18))
      let sizeDelta = ethers.utils.parseUnits("50", 18);
      let posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      const uniFutures = await ethers.getContractAt("IFuturesMarket", UNI_MARKET, account0)

      await marginManager.openPosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET, UNI_MARKET], [trData, posData])
      console.log(await marginAccount.positions(SNX_MARKET_KEY_sUNI))
      trData = await transferMarginData(accAddress, ethers.utils.parseUnits("-900", 18))
      sizeDelta = ethers.utils.parseUnits("-50", 18);
      posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))

      await marginManager.updatePosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET, UNI_MARKET], [posData, trData])
      console.log(await marginAccount.positions(SNX_MARKET_KEY_sUNI))

    });
    it("MarginAccount add/close position", async () => {

      await usdc.approve(accAddress, ethers.utils.parseUnits("5000", 6))
      await CollateralManager.addCollateral(usdc.address, ethers.utils.parseUnits("5000", 6))


      let trData = await transferMarginData(accAddress, ethers.utils.parseUnits("1000", 18))
      let sizeDelta = ethers.utils.parseUnits("50", 18);
      let posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      const uniFutures = await ethers.getContractAt("IFuturesMarket", UNI_MARKET, account0)

      await marginManager.openPosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET, UNI_MARKET], [trData, posData])
      console.log(await marginAccount.positions(SNX_MARKET_KEY_sUNI))
      trData = await transferMarginData(accAddress, ethers.utils.parseUnits("-900", 18))
      sizeDelta = ethers.utils.parseUnits("-50", 18);
      posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))

      await marginManager.closePosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET, UNI_MARKET], [posData, trData])
      console.log(await marginAccount.positions(SNX_MARKET_KEY_sUNI))

    });
    it("MarginAccount add position:snx case", async () => {

      await usdc.approve(accAddress, ethers.utils.parseUnits("6500", 6))
      await CollateralManager.addCollateral(usdc.address, ethers.utils.parseUnits("6500", 6))
      const EthFutures = await ethers.getContractAt("IFuturesMarket", ETH_MARKET, account0)

      let trData = await transferMarginData(accAddress, ethers.utils.parseUnits("2000", 18))
      let sizeDelta = ethers.utils.parseUnits("1", 18);
      let posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      // const uniFutures = await ethers.getContractAt("IFuturesMarket", UNI_MARKET, account0)
      console.log('po')
      let out = await marginManager.openPosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET, UNI_MARKET], [trData, posData])
      console.log('PO')
      const snxOwner = await ethers.getImpersonatedSigner("0x6d4a64C57612841c2C6745dB2a4E4db34F002D20");
      const EXCABI = (
        await artifacts.readArtifact(
          "contracts/Interfaces/SNX/ExchangeRates.sol:ExchangeRates"
        )
      ).abi;
      const _CB = (
        await artifacts.readArtifact(
          "contracts/Interfaces/SNX/ExchangeRates.sol:ICircuitBreaker"
        )
      ).abi;
      const RelayAbi = (
        await artifacts.readArtifact(
          "contracts/Interfaces/SNX/ExchangeRates.sol:relayer"
        )
      ).abi;
      // CircuitBreaker
      const CB = await ethers.getContractAt(_CB, "0x803FD1d99C3a6cbcbABAB79C44e108dC2fb67102")
      console.log("relay here", await EthFutures.assetPrice())
      let Relay: Contract = await ethers.getContractAt(RelayAbi, "0x6d4a64c57612841c2c6745db2a4e4db34f002d20")
      exchangeRates = await ethers.getContractAt(EXCABI, _exchangeRates, snxOwner);
      await setBalance(snxOwner.address, ethers.utils.parseUnits("10", 18));

      console.log('exchange rate:', await exchangeRates.address, await exchangeRates.nominatedOwner(), await exchangeRates.owner())
      // set the rate
      trData = await transferMarginData(accAddress, ethers.utils.parseUnits("8000", 18))
      sizeDelta = ethers.utils.parseUnits("10", 18);
      posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))

      console.log(ETH_MARKET, ":", await EthFutures.baseAsset(), await EthFutures.assetPrice());
      //positions,posData,
      reciept = await marginManager.openPosition(SNX_MARKET_KEY_sETH, [ETH_MARKET, ETH_MARKET], [trData, posData])
      console.log("eth market position", await EthFutures.positions(accAddress))
      let parsedAmount = ethers.utils.parseUnits("6000", 6)

      const approveAmountCalldata = await getErc20ApprovalCalldata(perpVault.address, parsedAmount);
      console.log("approveAmountCalldata - ", approveAmountCalldata);

      const fundVaultCalldata = await getVaultDepositCalldata(erc20.usdc, parsedAmount);
      console.log("fundVaultCalldata - ", fundVaultCalldata);
      const _perpOpenPositionCallData = await perpOpenPositionCallData(
        "0x34235C8489b06482A99bb7fcaB6d7c467b92d248",
        false,
        true,
        ethers.BigNumber.from('0'),
        ethers.utils.parseUnits("5000", 6),
        ethers.BigNumber.from('0'),
        ethers.constants.MaxUint256,
        ethers.constants.HashZero)

      console.log("perpOpenPositionCallData - ", _perpOpenPositionCallData, "--------------\n", await usdc.balanceOf(accAddress))
      reciept = await marginManager.openPosition(
        PERP_MARKET_KEY_AAVE,
        [erc20.usdc, perpVault.address, perpClearingHouse.address],
        [approveAmountCalldata, fundVaultCalldata, _perpOpenPositionCallData]
      );
      await exchangeRates.addAggregator(MARKET_KEY_sETH, mockAggregator.address);
      let { timestamp } = await ethers.provider.getBlock("latest");
      console.log(timestamp, "TS")
      await mockAggregator.connect(account0).setLatestAnswer(ethers.utils.parseUnits("1100", 18), timestamp);
      await CB.connect(snxOwner).resetLastValue([mockAggregator.address], [ethers.utils.parseUnits("1100", 18)])
      console.log("eth market position:1", await EthFutures.positions(accAddress))
      console.log(await CB.lastValue(mockAggregator.address), "last value", await CB.circuitBroken(mockAggregator.address))
      trData = await transferMarginData(accAddress, ethers.utils.parseUnits("-6000", 18))
      sizeDelta = ethers.utils.parseUnits("-10", 18);
      posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      // await mine(10, { interval: 15 });
      console.log(ETH_MARKET, ":....", await EthFutures.baseAsset(), await EthFutures.assetPrice());
      reciept = await marginManager.liquidate([SNX_MARKET_KEY_sETH], [ETH_MARKET], [posData])
      // await marginManager.liquidate([ETH_MARKET], [trData])
      console.log("mining new blocks:...\n")
      // await mineUpTo(36202194)
      //ExchangeRates
      console.log("After mining new blocks:...\n")
      console.log("eth market position", await EthFutures.positions(accAddress))
      console.log(await marginAccount.positions(PERP_MARKET_KEY_AAVE), await marginAccount.positions(SNX_MARKET_KEY_sUNI), await marginAccount.positions(SNX_MARKET_KEY_sETH))
    });
    it.only("MarginAccount add position:perpfi case", async () => {

      // await usdc.approve(accAddress, ethers.utils.parseUnits("6500", 6))
      // await CollateralManager.addCollateral(usdc.address, ethers.utils.parseUnits("6500", 6))
      // const EthFutures = await ethers.getContractAt("IFuturesMarket", ETH_MARKET, account0)

      // let trData = await transferMarginData(accAddress, ethers.utils.parseUnits("7000", 18))
      // let sizeDelta = ethers.utils.parseUnits("830", 18);
      // let posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      // // const uniFutures = await ethers.getContractAt("IFuturesMarket", UNI_MARKET, account0)
      // console.log("pending fee 0", await marginAccount.pendingFee())
      // let out = await marginManager.openPosition(SNX_MARKET_KEY_sUNI, [UNI_MARKET, UNI_MARKET], [trData, posData])
      // const perpfiOwner = await ethers.getImpersonatedSigner("0x76Ff908b6d43C182DAEC59b35CebC1d7A17D8086");
      // const EXCABI = (
      //   await artifacts.readArtifact(
      //     "contracts/Interfaces/Perpfi/IBaseToken.sol:IBaseToken"
      //   )
      // ).abi;
      // const baseToken = await ethers.getContractAt(EXCABI, "0x34235C8489b06482A99bb7fcaB6d7c467b92d248", perpfiOwner)
      // //ChainlinkPriceFeedV2 .new mockedAggregator.address,
      // const priceFeedFactory = await await ethers.getContractFactory("ChainlinkPriceFeedV2")
      // const priceFeed = await priceFeedFactory.deploy(mockAggregator.address, 0)
      // // cacheTwapInterval,
      // console.log("BaseToken owner", await baseToken.owner())
      // //setPriceFeed (ChainlinkPriceFeedV2)

      // await setBalance(perpfiOwner.address, ethers.utils.parseUnits("10", 18));
      // await baseToken.setPriceFeed(priceFeed.address)
      // console.log('exchange rate:')
      // // let iface = new ethers.utils.Interface(EXCABI)
      // // let addAGGdata = await iface.encodeFunctionData("addAggregator", [SNX_MARKET_KEY_sETH, mockAggregator.address])
      // // console.log(":relay owner", await Relay.temporaryOwner(), await Relay.expiryTime())

      // // // 
      // // set the rate
      // let { timestamp } = await ethers.provider.getBlock("latest");
      // console.log(timestamp, "pre set")
      // // const res = await Relay.directRelay(_exchangeRates, addAGGdata)
      // console.log("woho add done", await mockAggregator.latestRoundData())
      // await mockAggregator.connect(account0).setLatestAnswer(ethers.utils.parseUnits("60", 18), timestamp);
      // await priceFeed.update()
      // // {
      // //   await mine()
      // //   let { timestamp } = await ethers.provider.getBlock("latest");
      // //   await mockAggregator.connect(account0).setLatestAnswer(ethers.utils.parseUnits("59", 18), timestamp);
      // //   await priceFeed.update()
      // // }
      // // {
      // //   await mine()
      // //   let { timestamp } = await ethers.provider.getBlock("latest");
      // //   await mockAggregator.connect(account0).setLatestAnswer(ethers.utils.parseUnits("58", 18), timestamp);
      // //   await priceFeed.update()
      // // }
      // await mockAggregator.connect(account0).setLatestAnswer(ethers.utils.parseUnits("58", 18), timestamp + 15);
      // await priceFeed.update()

      // console.log("woho add done", await mockAggregator.latestRoundData())
      // trData = await transferMarginData(accAddress, ethers.utils.parseUnits("8000", 18))
      // sizeDelta = ethers.utils.parseUnits("10", 18);
      // posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      // console.log("yohoooo")
      // // console.log(ETH_MARKET, ":", await EthFutures.baseAsset(), await EthFutures.assetPrice());
      // //positions,posData,
      // console.log("pending fee 1", await marginAccount.pendingFee())
      // reciept = await marginManager.openPosition(SNX_MARKET_KEY_sETH, [ETH_MARKET, ETH_MARKET], [trData, posData])
      // console.log("eth market position", await EthFutures.positions(accAddress))

      // out = await out.wait()
      // let obj = out.events
      let parsedAmount = ethers.utils.parseUnits("6000", 6)

      const approveAmountCalldata = await getErc20ApprovalCalldata(perpVault.address, parsedAmount);
      console.log("approveAmountCalldata - ", approveAmountCalldata);

      const fundVaultCalldata = await getVaultDepositCalldata(erc20.usdc, parsedAmount);
      console.log("fundVaultCalldata - ", fundVaultCalldata);
      const _perpOpenPositionCallData = await perpOpenPositionCallData(
        "0x34235C8489b06482A99bb7fcaB6d7c467b92d248",
        false,
        true,
        ethers.BigNumber.from('0'),
        ethers.utils.parseUnits("5000", 6),
        ethers.BigNumber.from('0'),
        ethers.constants.MaxUint256,
        ethers.constants.HashZero)

      console.log("perpOpenPositionCallData - ", _perpOpenPositionCallData, "--------------\n")
      // , await usdc.balanceOf(accAddress))
      // console.log("pending fee 2", await marginAccount.pendingFee())
      // reciept = await marginManager.openPosition(
      //   PERP_MARKET_KEY_AAVE,
      //   [erc20.usdc, perpVault.address, perpClearingHouse.address],
      //   [approveAmountCalldata, fundVaultCalldata, _perpOpenPositionCallData]
      // );
      // console.log(await accountBalance.connect(account0).getPnlAndPendingFee(accAddress), "PNL before 18")
      // {
      //   await mine()
      //   let { timestamp } = await ethers.provider.getBlock("latest");
      //   await mockAggregator.connect(account0).setLatestAnswer(ethers.utils.parseUnits("18", 18), timestamp + 15);
      //   await priceFeed.update()
      // }
      // trData = await transferMarginData(accAddress, ethers.utils.parseUnits("6000", 18))
      // sizeDelta = ethers.utils.parseUnits("-10", 18);
      // posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))

      // console.log(ETH_MARKET, ":....", await EthFutures.baseAsset(), await EthFutures.assetPrice(), await EthFutures.positions(accAddress));
      // //positions,posData,
      // console.log("pending fee 3", await marginAccount.pendingFee())
      // await marginManager.liquidate([SNX_MARKET_KEY_sETH], [ETH_MARKET], [posData])
      // console.log("pending fee 4", await marginAccount.pendingFee())
      // console.log(await marginAccount.positions(PERP_MARKET_KEY_AAVE), await marginAccount.positions(SNX_MARKET_KEY_sUNI), await marginAccount.positions(SNX_MARKET_KEY_sETH))
      // const outt = await accountBalance.connect(account0).getAccountInfo(accAddress, "0x34235C8489b06482A99bb7fcaB6d7c467b92d248")
      // console.log("eth market position", await EthFutures.positions(accAddress), await accountBalance.connect(account0).getPnlAndPendingFee(accAddress), outt)
    });
    it("MarginAccount add position: perpfi Fees", async () => {
      await usdc.approve(accAddress, ethers.utils.parseUnits("6500", 6))
      console.log("balanceOf", await usdc.balanceOf(account0.address), await CollateralManager.totalCollateralValue(accAddress))
      await CollateralManager.addCollateral(usdc.address, ethers.utils.parseUnits("6500", 6))
      let parsedAmount = ethers.utils.parseUnits("6000", 6)

      const approveAmountCalldata = await getErc20ApprovalCalldata(perpVault.address, parsedAmount);

      const fundVaultCalldata = await getVaultDepositCalldata(erc20.usdc, parsedAmount);
      let _perpOpenPositionCallData = await perpOpenPositionCallData(
        "0x34235C8489b06482A99bb7fcaB6d7c467b92d248",
        false,
        true,
        ethers.BigNumber.from('0'),
        ethers.utils.parseUnits("5000", 6),
        ethers.BigNumber.from('0'),
        ethers.constants.MaxUint256,
        ethers.constants.HashZero)

      console.log("perpOpenPositionCallData - ", _perpOpenPositionCallData, "--------------\n", await usdc.balanceOf(accAddress))
      reciept = await marginManager.openPosition(
        PERP_MARKET_KEY_AAVE,
        [erc20.usdc, perpVault.address, perpClearingHouse.address],
        [approveAmountCalldata, fundVaultCalldata, _perpOpenPositionCallData]
      );
      console.log("Price", await perpClearingHouse.getPrice("0x34235C8489b06482A99bb7fcaB6d7c467b92d248"), await accountBalance.connect(account0).getPnlAndPendingFee(accAddress), await accountBalance.connect(account0).getAccountInfo(accAddress, "0x34235C8489b06482A99bb7fcaB6d7c467b92d248"), ":PNL")
      const perpfiOwner = await ethers.getImpersonatedSigner("0x76Ff908b6d43C182DAEC59b35CebC1d7A17D8086");
      const EXCABI = (
        await artifacts.readArtifact(
          "contracts/Interfaces/Perpfi/IBaseToken.sol:IBaseToken"
        )
      ).abi;
      const baseToken = await ethers.getContractAt(EXCABI, "0x34235C8489b06482A99bb7fcaB6d7c467b92d248", perpfiOwner)
      const priceFeedFactory = await await ethers.getContractFactory("ChainlinkPriceFeedV2")
      const priceFeed = await priceFeedFactory.deploy(mockAggregator.address, 0)
      // cacheTwapInterval,
      console.log("BaseToken owner", await baseToken.owner())

      await setBalance(perpfiOwner.address, ethers.utils.parseUnits("10", 18));
      await baseToken.setPriceFeed(priceFeed.address)
      {
        await mine()
        let { timestamp } = await ethers.provider.getBlock("latest");
        await mockAggregator.connect(account0).setLatestAnswer(ethers.utils.parseUnits("59", 18), timestamp);
        await priceFeed.update()
      }
      await accountBalance.connect(account0).getAccountInfo(accAddress, "0x34235C8489b06482A99bb7fcaB6d7c467b92d248")
      // console.log(await perpClearingHouse.getAccountValue(accAddress))
      const pnl = await accountBalance.connect(account0).getPnlAndPendingFee(accAddress)
      console.log(pnl, await perpVault.getFreeCollateralByToken(accAddress, erc20.usdc))
      let wamt = (await perpVault.getFreeCollateralByToken(accAddress, erc20.usdc)).add(pnl.unrealizedPnl)
      console.log(wamt, "withdraw amount", await usdc.balanceOf(accAddress))
      let withdrawData = await getVaultWithdrawCalldata(erc20.usdc, await perpVault.getFreeCollateralByToken(accAddress, erc20.usdc))
      let _perpClosePositionCallData = await getClosePerpPositionCalldata(
        "0x34235C8489b06482A99bb7fcaB6d7c467b92d248",
        ethers.BigNumber.from('0'),
        ethers.BigNumber.from('0'),
        ethers.constants.MaxUint256,
        ethers.constants.HashZero)
      console.log(_perpClosePositionCallData, 'perp close data')
      reciept = await marginManager.closePosition(
        PERP_MARKET_KEY_AAVE,
        [perpClearingHouse.address, perpVault.address],//, perpVault.address
        [_perpClosePositionCallData, withdrawData]
      );
      console.log(withdrawData)
      console.log(await accountBalance.connect(account0).getPnlAndPendingFee(accAddress), ":PNL")
      const x1 = await usdc.balanceOf(account0.address)
      const x2 = await usdc.balanceOf(accAddress)
      const x3 = await usdc.balanceOf(vault.address)
      console.log("balanceOf:", x1, x2, x3, x1.add(x2).add(x3), await perpClearingHouse.getAccountValue(accAddress), await accountBalance.connect(account0).getPnlAndPendingFee(accAddress), await accountBalance.connect(account0).getTotalAbsPositionValue(accAddress))

      // console.log('exchange rate:')
      // let { timestamp } = await ethers.provider.getBlock("latest");
      // console.log(timestamp, "pre set")
      // console.log("woho add done", await mockAggregator.latestRoundData())
      // await mockAggregator.connect(account0).setLatestAnswer(ethers.utils.parseUnits("60", 18), timestamp);
      // await priceFeed.update()
    });
    it("MarginAccount add position:snx Fees", async () => {

      await usdc.approve(accAddress, ethers.utils.parseUnits("6500", 6))
      await CollateralManager.addCollateral(usdc.address, ethers.utils.parseUnits("6500", 6))
      const EthFutures = await ethers.getContractAt("IFuturesMarket", ETH_MARKET, account0)

      let trData = await transferMarginData(accAddress, ethers.utils.parseUnits("6500", 18))
      let sizeDelta = ethers.utils.parseUnits("5", 18);
      let posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      let out = await marginManager.openPosition(SNX_MARKET_KEY_sETH, [ETH_MARKET, ETH_MARKET], [trData, posData])
      console.log(await EthFutures.positions(accAddress), await EthFutures.assetPrice(), "AFter first trade")
      const snxOwner = await ethers.getImpersonatedSigner("0x6d4a64C57612841c2C6745dB2a4E4db34F002D20");
      const EXCABI = (
        await artifacts.readArtifact(
          "contracts/Interfaces/SNX/ExchangeRates.sol:ExchangeRates"
        )
      ).abi;
      const _CB = (
        await artifacts.readArtifact(
          "contracts/Interfaces/SNX/ExchangeRates.sol:ICircuitBreaker"
        )
      ).abi;
      // CircuitBreaker
      const CB = await ethers.getContractAt(_CB, "0x803FD1d99C3a6cbcbABAB79C44e108dC2fb67102")
      exchangeRates = await ethers.getContractAt(EXCABI, _exchangeRates, snxOwner);
      await setBalance(snxOwner.address, ethers.utils.parseUnits("10", 18));

      sizeDelta = ethers.utils.parseUnits("-5", 18);
      posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))

      reciept = await marginManager.updatePosition(SNX_MARKET_KEY_sETH, [ETH_MARKET], [posData])
      console.log(await EthFutures.positions(accAddress), await EthFutures.assetPrice(), "AFter close trade")
      // await exchangeRates.addAggregator(MARKET_KEY_sETH, mockAggregator.address);
      // let { timestamp } = await ethers.provider.getBlock("latest");
      // console.log(timestamp, "TS")
      // await mockAggregator.connect(account0).setLatestAnswer(ethers.utils.parseUnits("1100", 18), timestamp);
      // await CB.connect(snxOwner).resetLastValue([mockAggregator.address], [ethers.utils.parseUnits("1100", 18)])
      // console.log("eth market position:1", await EthFutures.positions(accAddress))
      // console.log(await CB.lastValue(mockAggregator.address), "last value", await CB.circuitBroken(mockAggregator.address))
      // trData = await transferMarginData(accAddress, ethers.utils.parseUnits("-6000", 18))
      // sizeDelta = ethers.utils.parseUnits("-10", 18);
      // posData = await openPositionData(sizeDelta, ethers.utils.formatBytes32String("GIGABRAINs"))
      // console.log(ETH_MARKET, ":....", await EthFutures.baseAsset(), await EthFutures.assetPrice());
      // reciept = await marginManager.liquidate([SNX_MARKET_KEY_sETH], [ETH_MARKET], [posData])
      // console.log("eth market position", await EthFutures.positions(accAddress))
      // console.log(await marginAccount.positions(SNX_MARKET_KEY_sUNI), await marginAccount.positions(SNX_MARKET_KEY_sETH))
    });
  });
});

