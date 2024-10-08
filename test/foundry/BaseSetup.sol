// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "ds-test/test.sol";
import "forge-std/console2.sol";
import {Vault} from "../../contracts/MarginPool/Vault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// force update
import {ContractRegistry} from "../../contracts/Utils/ContractRegistry.sol";
import {CollateralManager} from "../../contracts/CollateralManager.sol";
import {MarketManager} from "../../contracts/MarketManager.sol";
import {MarginAccountFactory} from "../../contracts/MarginAccount/MarginAccountFactory.sol";
import {RiskManager} from "../../contracts/RiskManager/RiskManager.sol";
import {SNXRiskManager} from "../../contracts/RiskManager/SNXRiskManager.sol";
import {PerpfiRiskManager} from "../../contracts/RiskManager/PerpfiRiskManager.sol";
import {MarginManager} from "../../contracts/MarginManager.sol";
import {PriceOracle} from "../../contracts/Utils/PriceOracle.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {LinearInterestRateModel} from "../../contracts/MarginPool/LinearInterestRateModel.sol";
import {IAddressResolver} from "../../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IProtocolRiskManager} from "../../contracts/Interfaces/IProtocolRiskManager.sol";
import {IContractRegistry} from "../../contracts/Interfaces/IContractRegistry.sol";
import {IPriceOracle} from "../../contracts/Interfaces/IPriceOracle.sol";
import {IMarketManager} from "../../contracts/Interfaces/IMarketManager.sol";
import {IMarginManager} from "../../contracts/Interfaces/IMarginManager.sol";
import {IRiskManager} from "../../contracts/Interfaces/IRiskManager.sol";
import {IMarginAccount} from "../../contracts/Interfaces/IMarginAccount.sol";
import {ICollateralManager} from "../../contracts/Interfaces/ICollateralManager.sol";
import {IInterestRateModel} from "../../contracts/Interfaces/IInterestRateModel.sol";
import {IFuturesMarketManager} from "../../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
import {ICircuitBreaker} from "../../contracts/Interfaces/SNX/ICircuitBreaker.sol";
import {ISystemStatus} from "../../contracts/Interfaces/SNX/ISystemStatus.sol";
import {Utils} from "./utils/Utils.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IEvents} from "./IEvents.sol";
import {ACLManager} from "../../contracts/Utils/ACLManager.sol";

struct RoundData {
    uint80 roundId;
    int256 answer;
    uint256 startedAt;
    uint256 updatedAt;
    uint80 answeredInRound;
}

// The following interface is inherited by BaseSetup for exposing all its public functions.

contract BaseSetup is Test, IEvents {
    // ============= Libraries =============

    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    // ============= Utils =============
    Utils internal utils;
    Contracts internal contracts;
    uint256 RAY = 10 ** 27;
    uint256 WAD = 10 ** 18;

    // ============= Users =============
    address payable[] internal users;
    address public admin;
    address public alice;
    address public bob;
    address internal charlie;
    address internal david;
    address internal deployerAdmin;

    // ============= Forked Addresses =============

    address usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address usdt = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;
    address usdcWhaleContract = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
    address susdWhaleContract = 0xd16232ad60188B68076a235c65d692090caba155;
    address susd = 0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9;

    address perpAccountBalance = 0xA7f3FC32043757039d5e13d790EE43edBcBa8b7c;
    address perpMarketRegistry = 0xd5820eE0F55205f6cdE8BB0647072143b3060067;
    address perpClearingHouse = 0x82ac2CE43e33683c58BE4cDc40975E73aA50f459;
    address perpClearingHouseConfig =
        0xA4c817a425D3443BAf610CA614c8B11688a288Fb;
    address perpAaveMarket = 0x34235C8489b06482A99bb7fcaB6d7c467b92d248;
    address perpEthMarket = 0x8C835DFaA34e2AE61775e80EE29E2c724c6AE2BB;
    address perpVault = 0xAD7b4C162707E0B2b5f6fdDbD3f8538A5fbA0d60;
    address perpExchange = 0xBd7a3B7DbEb096F0B832Cf467B94b091f30C34ec;
    // synthetix (ReadProxyAddressResolver)
    address SNX_ADDRESS_RESOLVER = 0x1Cb059b7e74fD21665968C908806143E744D5F30;
    // address futuresMarketSettings = 0x0dde87714C3bdACB93bB1d38605aFff209a85998;
    address futuresMarketSettings = 0xaE55F163337A2A46733AA66dA9F35299f9A46e9e;
    address sUsdPriceFeed = 0x7f99817d87baD03ea21E05112Ca799d715730efe;
    address usdcPriceFeed = 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;
    address etherPriceFeed = 0x13e3Ee699D1909E989722E753853AE30b17e08c5;
    address snxFuturesMarketManager;
    address snxOwner = 0x6d4a64C57612841c2C6745dB2a4E4db34F002D20;
    address circuitBreaker = 0x803FD1d99C3a6cbcbABAB79C44e108dC2fb67102;
    address exchangeRates = 0x913bd76F7E1572CC8278CeF2D6b06e2140ca9Ce2;
    address systemStatus = 0xE8c41bE1A167314ABAF2423b72Bf8da826943FFD;
    address exchangeCircuitBreaker = 0x7322e8F6cB6c6a7B4e6620C486777fcB9Ea052a4;
    bytes32 perpAaveKey = keccak256("PERP.AAVE");
    bytes32 invalidKey = keccak256("BKL.MKC");
    bytes32 snxUniKey = keccak256("SNX.UNI");
    bytes32 snxEthKey = keccak256("SNX.ETH");
    bytes32 snxUni_marketKey = bytes32("sUNI");
    bytes32 snxEth_marketKey = bytes32("sETH");
    uint256 constant ONE_MILLION_USDC = 1_000_000 * ONE_USDC;
    uint256 constant ONE_MILLION_SUSD = 1_000_000 ether;
    uint256 constant CENT = 100;
    uint256 constant ONE_USDC = 10 ** 6;
    int256 constant ONE_USDC_INT = 10 ** 6;
    address bobMarginAccount;
    address aliceMarginAccount;
    address uniFuturesMarket;
    address ethFuturesMarket;

    // ============= Setup Functions =============

    function setupUsers() internal {
        users = utils.createUsers(6);
        deployerAdmin = users[5];
        vm.label(deployerAdmin, "deployerAdmin");
        vm.deal(deployerAdmin, 1000 ether);
        admin = users[0];
        vm.label(admin, "Admin");
        vm.deal(admin, 1000 ether);
        alice = users[1];
        vm.label(alice, "Alice");
        vm.deal(alice, 1000 ether);
        bob = users[2];
        vm.label(bob, "Bob");
        vm.deal(bob, 1000 ether);
        charlie = users[3];
        vm.label(charlie, "charlie");
        vm.deal(charlie, 1000 ether);
        david = users[4];
        vm.label(david, "david");
        vm.deal(david, 1000 ether);
    }

    function setupContractRegistry() internal {
        vm.startPrank(deployerAdmin);
        contracts.contractRegistry = new ContractRegistry();
        vm.stopPrank();
    }

    function setupMarketManager() internal {
        vm.startPrank(deployerAdmin);
        contracts.marketManager = new MarketManager(
            address(contracts.contractRegistry)
        );
        contracts.contractRegistry.addContractToRegistry(
            keccak256("MarketManager"),
            address(contracts.marketManager)
        );
    }

    function setupACLManager() internal {
        vm.startPrank(deployerAdmin);
        contracts.aclManager = new ACLManager(deployerAdmin);
        contracts.aclManager.grantRole(
            contracts.aclManager.CHRONUX_ADMIN_ROLE(),
            deployerAdmin
        );
        contracts.contractRegistry.addContractToRegistry(
            keccak256("AclManager"),
            address(contracts.aclManager)
        );
        vm.stopPrank();
    }

    function setupPriceOracle() internal {
        vm.startPrank(deployerAdmin);
        contracts.priceOracle = new PriceOracle();
        contracts.priceOracle.addPriceFeed(susd, sUsdPriceFeed);
        contracts.priceOracle.addPriceFeed(usdc, usdcPriceFeed);
        contracts.contractRegistry.addContractToRegistry(
            keccak256("PriceOracle"),
            address(contracts.priceOracle)
        );
        vm.stopPrank();
    }

    function setupMarginManager() internal {
        vm.startPrank(deployerAdmin);
        contracts.marginManager = new MarginManager(contracts.contractRegistry);
        contracts.contractRegistry.addContractToRegistry(
            keccak256("MarginManager"),
            address(contracts.marginManager)
        );
        contracts.aclManager.grantRole(
            contracts.aclManager.LEND_BORROW_MANAGER_ROLE(),
            address(contracts.marginManager)
        );
        contracts.aclManager.grantRole(
            contracts.aclManager.MARGIN_ACCOUNT_FUND_MANAGER_ROLE(),
            address(contracts.marginManager)
        );
        contracts.aclManager.grantRole(
            contracts.aclManager.CHRONUX_MARGIN_ACCOUNT_MANAGER_ROLE(),
            address(contracts.marginManager)
        );
        vm.stopPrank();
    }

    function setupRiskManager() internal {
        vm.startPrank(deployerAdmin);
        contracts.riskManager = new RiskManager(contracts.contractRegistry);
        contracts.contractRegistry.addContractToRegistry(
            keccak256("RiskManager"),
            address(contracts.riskManager)
        );
        vm.stopPrank();
    }

    function setupCollateralManager() internal {
        vm.startPrank(deployerAdmin);
        contracts.collateralManager = new CollateralManager(
            address(contracts.contractRegistry)
        );
        contracts.contractRegistry.addContractToRegistry(
            keccak256("CollateralManager"),
            address(contracts.collateralManager)
        );
        contracts.aclManager.grantRole(
            contracts.aclManager.MARGIN_ACCOUNT_FUND_MANAGER_ROLE(),
            address(contracts.collateralManager)
        );
        vm.stopPrank();
    }

    function setupMarginAccountFactory() internal {
        vm.startPrank(deployerAdmin);
        contracts.marginAccountFactory = new MarginAccountFactory(
            address(contracts.contractRegistry)
        );
        contracts.contractRegistry.addContractToRegistry(
            keccak256("MarginAccountFactory"),
            address(contracts.marginAccountFactory)
        );
        vm.stopPrank();
    }

    function setupVault(address token) internal {
        uint256 optimalUse = 80 * 10 ** 4;
        uint256 rBase = 0;
        uint256 rSlope1 = 2 * 10 ** 4;
        uint256 rSlope2 = 10 * 10 ** 4;
        vm.startPrank(deployerAdmin);
        contracts.interestModel = new LinearInterestRateModel(
            optimalUse,
            rBase,
            rSlope1,
            rSlope2
        );
        // uint256 maxExpectedLiquidity = 1_000_000 * ERC20(token).decimals();
        contracts.vault = new Vault(
            address(contracts.aclManager),
            token,
            "GigaLP",
            "GLP",
            address(contracts.interestModel)
            // maxExpectedLiquidity
        );
        contracts.contractRegistry.addContractToRegistry(
            keccak256("InterestModel"),
            address(contracts.interestModel)
        );
        contracts.contractRegistry.addContractToRegistry(
            keccak256("Vault"),
            address(contracts.vault)
        );
        vm.stopPrank();
    }

    function setupProtocolRiskManagers() internal {
        vm.startPrank(deployerAdmin);
        contracts.perpfiRiskManager = new PerpfiRiskManager(
            usdc,
            address(contracts.contractRegistry),
            perpAccountBalance,
            perpMarketRegistry,
            perpClearingHouse,
            perpVault,
            18
        );
        contracts.snxRiskManager = new SNXRiskManager(
            susd,
            address(contracts.contractRegistry),
            18
        );
        contracts.contractRegistry.addContractToRegistry(
            keccak256("PerpfiRiskManager"),
            address(contracts.perpfiRiskManager)
        );
        contracts.contractRegistry.addContractToRegistry(
            keccak256("SnxRiskManager"),
            address(contracts.snxRiskManager)
        );
        vm.stopPrank();
    }

    function _setupCommonFixture(address vaultAsset) internal {
        snxFuturesMarketManager = IAddressResolver(SNX_ADDRESS_RESOLVER)
            .getAddress(bytes32("FuturesMarketManager"));
        uniFuturesMarket = IFuturesMarketManager(snxFuturesMarketManager)
            .marketForKey(snxUni_marketKey);
        vm.label(uniFuturesMarket, "UNI futures Market");
        ethFuturesMarket = IFuturesMarketManager(snxFuturesMarketManager)
            .marketForKey(snxEth_marketKey);
        vm.label(ethFuturesMarket, "ETH futures Market");
        setupUsers();
        setupContractRegistry();
        setupACLManager();
        setupPriceOracle();
        setupMarketManager();
        setupMarginManager();
        setupMarginAccountFactory();
        setupRiskManager();
        setupVault(vaultAsset);
        setupCollateralManager();
        vm.startPrank(deployerAdmin);
        vm.stopPrank();
        setupProtocolRiskManagers();
        vm.startPrank(deployerAdmin);
        contracts.collateralManager.whitelistCollateral(usdc, 100);
        contracts.collateralManager.whitelistCollateral(susd, 100);
        vm.stopPrank();

        // Fund admin traders
        vm.startPrank(usdcWhaleContract);
        IERC20(usdc).transfer(admin, 2 * ONE_MILLION_USDC);
        IERC20(usdc).transfer(bob, ONE_MILLION_USDC);
        IERC20(usdc).transfer(alice, ONE_MILLION_USDC);
        vm.stopPrank();
        vm.startPrank(susdWhaleContract);
        IERC20(susd).transfer(admin, 2 * ONE_MILLION_SUSD);
        IERC20(susd).transfer(bob, ONE_MILLION_SUSD);
        IERC20(susd).transfer(alice, ONE_MILLION_SUSD);
        vm.stopPrank();
        // Fund Vault
        vm.startPrank(admin);
        uint256 vaultDepositAmount = ONE_MILLION_USDC;
        if (vaultAsset == susd) {
            vaultDepositAmount = ONE_MILLION_SUSD;
        }
        IERC20(vaultAsset).approve(
            address(contracts.vault),
            vaultDepositAmount
        );
        contracts.vault.deposit(vaultDepositAmount, admin);
        vm.stopPrank();
        //  open Margin Accounts
        vm.prank(bob);
        bobMarginAccount = contracts.marginManager.openMarginAccount();
        vm.prank(alice);
        aliceMarginAccount = contracts.marginManager.openMarginAccount();

        // Set mock response for price oracle
        makeSusdAndUsdcEqualToOne();

        // Set Mock response of SNX Probe Circuit Broken to false always
        vm.mockCall(
            circuitBreaker,
            abi.encodeWithSelector(
                ICircuitBreaker.probeCircuitBreaker.selector
            ),
            abi.encode(false)
        );

        vm.mockCall(
            systemStatus,
            abi.encodeWithSelector(ISystemStatus.synthSuspended.selector),
            abi.encode(false)
        );
    }

    function addMarkets() internal {
        vm.startPrank(deployerAdmin);
        contracts.marketManager.addMarket(
            snxUniKey,
            uniFuturesMarket,
            address(contracts.snxRiskManager),
            address(0),
            susd
        );
        contracts.marketManager.addMarket(
            snxEthKey,
            ethFuturesMarket,
            address(contracts.snxRiskManager),
            address(0),
            susd
        );
        contracts.snxRiskManager.toggleAddressWhitelisting(
            uniFuturesMarket,
            true
        );
        contracts.snxRiskManager.toggleAddressWhitelisting(
            ethFuturesMarket,
            true
        );
        contracts.marketManager.addMarket(
            perpAaveKey,
            perpClearingHouse,
            address(contracts.perpfiRiskManager),
            perpAaveMarket,
            usdc
        );

        contracts.perpfiRiskManager.toggleAddressWhitelisting(
            perpClearingHouse,
            true
        );
        contracts.perpfiRiskManager.toggleAddressWhitelisting(usdc, true);
        contracts.perpfiRiskManager.toggleAddressWhitelisting(perpVault, true);
        vm.stopPrank();
    }

    function setupPrmFixture() internal {
        _setupCommonFixture(usdc);
        addMarkets();
        vm.startPrank(deployerAdmin);
        contracts.contractRegistry.addCurvePool(
            usdc,
            susd,
            0x061b87122Ed14b9526A813209C8a59a633257bAb
        );
        contracts.contractRegistry.addCurvePool(
            susd,
            usdc,
            0x061b87122Ed14b9526A813209C8a59a633257bAb
        );
        contracts.contractRegistry.updateCurvePoolTokenIndex(
            0x061b87122Ed14b9526A813209C8a59a633257bAb,
            susd,
            0
        );
        contracts.contractRegistry.updateCurvePoolTokenIndex(
            0x061b87122Ed14b9526A813209C8a59a633257bAb,
            usdc,
            2
        );
        vm.stopPrank();
    }

    function makeSusdAndUsdcEqualToOne() internal {
        RoundData memory stablesRoundData = RoundData(
            18446744073709552872,
            100000000,
            block.timestamp - 0,
            block.timestamp - 0,
            18446744073709552872
        );
        vm.mockCall(
            sUsdPriceFeed,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                stablesRoundData.roundId,
                stablesRoundData.answer,
                stablesRoundData.startedAt,
                stablesRoundData.updatedAt,
                stablesRoundData.answeredInRound
            )
        );
        vm.mockCall(
            usdcPriceFeed,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                stablesRoundData.roundId,
                stablesRoundData.answer,
                stablesRoundData.startedAt,
                stablesRoundData.updatedAt,
                stablesRoundData.answeredInRound
            )
        );
    }

    // function setup() public {
    // contracts.utils = new Utils();
    // setupUsers();
    // setupContractRegistry();
    // setupPriceOracle();
    // setupMarketManager();
    // setupMarginManager();
    // setupRiskManagers();
    // setupCollateralManager();
    // setupVault();
    // riskManager.setCollateralManager(collateralManager);
    // riskManager.setVault(vault);
    // setupProtocolRiskManagers();
    // collateralManager.whitelistCollateral([usdc, susd], [100, 100]);
    // marketManager.addMarket(_marketName, _market, _riskManager);
    //fetch
    // snxFuturesMarketManager = IAddressResolver(SYN_ADDRESS_RESOLVER).getAddress(keccak256("FuturesMarketManager"));
    // }
}
