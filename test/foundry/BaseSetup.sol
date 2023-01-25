// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "ds-test/test.sol";
import "forge-std/console2.sol";
import {Vault} from "../../contracts/MarginPool/Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ContractRegistry} from "../../contracts/utils/ContractRegistry.sol";
import {CollateralManager} from "../../contracts/CollateralManager.sol";
import {MarketManager} from "../../contracts/MarketManager.sol";
import {RiskManager} from "../../contracts/RiskManager/RiskManager.sol";
import {SNXRiskManager} from "../../contracts/RiskManager/SNXRiskManager.sol";
import {PerpfiRiskManager} from "../../contracts/RiskManager/PerpfiRiskManager.sol";
import {MarginManager} from "../../contracts/MarginManager.sol";
import {PriceOracle} from "../../contracts/utils/PriceOracle.sol";

import {LinearInterestRateModel} from "../../contracts/MarginPool/LinearInterestRateModel.sol";
import {IAddressResolver} from "../../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IProtocolRiskManager} from "../../contracts/Interfaces/IProtocolRiskManager.sol";
import {IInterestRateModel} from "../../contracts/Interfaces/IInterestRateModel.sol";
import {IFuturesMarketManager} from "../../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
import {Utils} from "./utils/Utils.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BaseSetup is Test {
    // ============= Libraries =============

    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SignedMath for int256;

    // ============= Utils =============
    Utils internal utils;
    uint256 RAY = 10**27;
    uint256 WAD = 10**18;

    // ============= Users =============
    address payable[] internal users;
    address public admin;
    address public alice;
    address public bob;
    address internal charlie;
    address internal david;

    // ============= Contracts =============

    ContractRegistry contractRegistry;
    PriceOracle priceOracle;
    MarketManager marketManager;
    CollateralManager collateralManager;
    MarginManager marginManager;
    RiskManager riskManager;
    IProtocolRiskManager perpfiRiskManager;
    IProtocolRiskManager snxRiskManager;
    IInterestRateModel interestModel;
    Vault vault;

    // ============= Forked Addresses =============

    address usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address usdcWhaleContract = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
    address susd = 0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9;

    address perpAccountBalance = 0xA7f3FC32043757039d5e13d790EE43edBcBa8b7c;
    address perpClearingHouse = 0x82ac2CE43e33683c58BE4cDc40975E73aA50f459;
    // synthetix (ReadProxyAddressResolver)
    address SNX_ADDRESS_RESOLVER = 0x1Cb059b7e74fD21665968C908806143E744D5F30;

    address sUsdPriceFeed = 0x7f99817d87baD03ea21E05112Ca799d715730efe;
    address usdcPriceFeed = 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;
    address snxFuturesMarketManager;

    // ======================================= Test Events =======================================

    // ============= Collateral Manager Events =============
    event CollateralAdded(
        address indexed,
        address indexed,
        uint256 indexed,
        uint256
    );

    // ============= Setup Functions =============

    function setupUsers() internal {
        users = utils.createUsers(5);
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
        contractRegistry = new ContractRegistry();
    }

    function setupMarketManager() internal {
        marketManager = new MarketManager();
        contractRegistry.addContractToRegistry(
            keccak256("MarketManager"),
            address(marketManager)
        );
    }

    function setupPriceOracle() internal {
        priceOracle = new PriceOracle();
        priceOracle.addPriceFeed(susd, sUsdPriceFeed);
        priceOracle.addPriceFeed(usdc, usdcPriceFeed);
    }

    function setupMarginManager() internal {
        marginManager = new MarginManager(
            contractRegistry,
            marketManager,
            priceOracle
        );
    }

    function setupRiskManager() internal {
        riskManager = new RiskManager(contractRegistry, marketManager);
        riskManager.setPriceOracle(address(priceOracle));
    }

    function setupCollateralManager() internal {
        collateralManager = new CollateralManager(
            address(marginManager),
            address(riskManager),
            address(priceOracle)
        );
    }

    function setupVault() internal {
        uint256 optimalUse = 9000;
        uint256 rBase = 0;
        uint256 rSlope1 = 200;
        uint256 rSlope2 = 1000;
        interestModel = new LinearInterestRateModel(
            optimalUse,
            rBase,
            rSlope1,
            rSlope2
        );
        uint256 maxExpectedLiquidity = 1_000_000 * (10**6);
        vault = new Vault(
            usdc,
            "GigaLP",
            "GLP",
            address(interestModel),
            maxExpectedLiquidity
        );
        vault.addLendingAddress(address(marginManager));
        vault.addRepayingAddress(address(marginManager));
    }

    function setupProtocolRiskManagers() internal {
        perpfiRiskManager = new PerpfiRiskManager(
            usdc,
            address(contractRegistry),
            perpAccountBalance
        );
        snxRiskManager = new SNXRiskManager(susd, address(contractRegistry));
    }

    // function setup() public {
    // utils = new Utils();
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
    // collateralManager.addAllowedCollateral([usdc, susd], [100, 100]);
    // marketManager.addMarket(_marketName, _market, _riskManager);
    //fetch
    // snxFuturesMarketManager = IAddressResolver(SYN_ADDRESS_RESOLVER).getAddress(keccak256("FuturesMarketManager"));
    // }
}
