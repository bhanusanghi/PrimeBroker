// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "ds-test/test.sol";
import "forge-std/console2.sol";
import {Vault} from "../contracts/MarginPool/Vault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// force update
import {ContractRegistry} from "../contracts/Utils/ContractRegistry.sol";
import {CollateralManager} from "../contracts/CollateralManager.sol";
import {MarketManager} from "../contracts/MarketManager.sol";
import {RiskManager} from "../contracts/RiskManager/RiskManager.sol";
import {SNXRiskManager} from "../contracts/RiskManager/SNXRiskManager.sol";
import {PerpfiRiskManager} from "../contracts/RiskManager/PerpfiRiskManager.sol";
import {MarginManager} from "../contracts/MarginManager.sol";
import {PriceOracle} from "../contracts/Utils/PriceOracle.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {LinearInterestRateModel} from "../contracts/MarginPool/LinearInterestRateModel.sol";
import {IAddressResolver} from "../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IProtocolRiskManager} from "../contracts/Interfaces/IProtocolRiskManager.sol";
import {IInterestRateModel} from "../contracts/Interfaces/IInterestRateModel.sol";
import {IFuturesMarketManager} from "../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
struct RoundData {
    uint80 roundId;
    int256 answer;
    uint256 startedAt;
    uint256 updatedAt;
    uint80 answeredInRound;
}

contract BaseDeployer {
    // ============= Libraries =============

    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    // ============= Utils =============
    uint256 RAY = 10 ** 27;
    uint256 WAD = 10 ** 18;

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

    // ============= Testnet Addresses =============

    address usdc = 0xe5e0DE0ABfEc2FFFaC167121E51d7D8f57C8D9bC;
    address susd = 0xeBaEAAD9236615542844adC5c149F86C36aD1136;
    address perpAccountBalance = 0xF59f28F21ad8905a7C797BeE2aeABccb53A5650a;
    address perpMarketRegistry = 0xE3376C2067115c86020339BC6a3879B4778f5b15;
    address perpClearingHouse = 0xaD2663386fe55e920c81D55Fc342fC50F91D86Ca;
    address perpEthMarket = 0x60A233b9b94c67e94e0a269429Fb40004D4BA494;
    address perpVault = 0x253D7430118Be0B961A5e938d003C6d690d7ce99;
    // synthetix (ReadProxyAddressResolver)
    address SNX_ADDRESS_RESOLVER = 0x1d551351613a28d676BaC1Af157799e201279198;
    address futuresMarketSettings = 0x0dde87714C3bdACB93bB1d38605aFff209a85998;
    address sUsdPriceFeed = 0x2636B223652d388721A0ED2861792DA9062D8C73; // keeping it same as usdc for now as there is no feed of susd on goerli op testnet
    address usdcPriceFeed = 0x2636B223652d388721A0ED2861792DA9062D8C73;
    address etherPriceFeed = 0x57241A37733983F97C4Ab06448F244A1E0Ca0ba8;
    address circuitBreaker = 0x5cB8210159f486dFE8Dc779357ee5A15B8f233bC;



    // ============= Forked Addresses =============

//    address usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
//    address usdcWhaleContract = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
//    address susdWhaleContract = 0xd16232ad60188B68076a235c65d692090caba155;
//    address susd = 0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9;
//
//    address perpAccountBalance = 0xA7f3FC32043757039d5e13d790EE43edBcBa8b7c;
//    address perpMarketRegistry = 0xd5820eE0F55205f6cdE8BB0647072143b3060067;
//    address perpClearingHouse = 0x82ac2CE43e33683c58BE4cDc40975E73aA50f459;
//    address perpEthMarket = 0x8C835DFaA34e2AE61775e80EE29E2c724c6AE2BB;
//    address perpVault = 0xAD7b4C162707E0B2b5f6fdDbD3f8538A5fbA0d60;
//    // synthetix (ReadProxyAddressResolver)
//    address SNX_ADDRESS_RESOLVER = 0x1Cb059b7e74fD21665968C908806143E744D5F30;
//    // address futuresMarketSettings = 0x0dde87714C3bdACB93bB1d38605aFff209a85998;
//    address futuresMarketSettings = 0xaE55F163337A2A46733AA66dA9F35299f9A46e9e;
//    address sUsdPriceFeed = 0x7f99817d87baD03ea21E05112Ca799d715730efe;
//    address usdcPriceFeed = 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;
//    address etherPriceFeed = 0x13e3Ee699D1909E989722E753853AE30b17e08c5;
//    address snxFuturesMarketManager;
//    address snxOwner = 0x6d4a64C57612841c2C6745dB2a4E4db34F002D20;
//    address circuitBreaker = 0x803FD1d99C3a6cbcbABAB79C44e108dC2fb67102;

    // ============= Setup Functions =============

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
        contractRegistry.addContractToRegistry("PriceOracle", address(priceOracle));
    }

    function setupMarginManager() internal {
        marginManager = new MarginManager(
            contractRegistry,
            priceOracle
        );
        contractRegistry.addContractToRegistry(
            keccak256("MarginManager"),
            address(marginManager)
        );
    }

    function setupRiskManager() internal {
        riskManager = new RiskManager(contractRegistry, marketManager);
//        riskManager.setPriceOracle(address(priceOracle));
        contractRegistry.addContractToRegistry(
            keccak256("RiskManager"),
            address(riskManager)
        );
    }

    function setupCollateralManager() internal {
        collateralManager = new CollateralManager(
            address(marginManager),
            address(riskManager),
            address(priceOracle),
            address(vault)
        );
        contractRegistry.addContractToRegistry(
            keccak256("CollateralManager"),
            address(collateralManager)
        );
    }

    function setupVault(address token) internal {
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
        // uint256 maxExpectedLiquidity = 1_000_000 * ERC20(token).decimals();
        vault = new Vault(
            token,
            "GigaLP",
            "GLP",
            address(interestModel)
            // maxExpectedLiquidity
        );
        vault.addLendingAddress(address(marginManager));
        vault.addRepayingAddress(address(marginManager));
        contractRegistry.addContractToRegistry(keccak256("Vault"), address(vault));
    }

    function setupProtocolRiskManagers() internal {
        perpfiRiskManager = new PerpfiRiskManager(
            usdc,
            address(contractRegistry),
            perpAccountBalance,
            perpMarketRegistry,
            perpClearingHouse,
            perpVault,
            ERC20(vault.asset()).decimals(),
            18
        );
        snxRiskManager = new SNXRiskManager(
            susd,
            address(contractRegistry),
            ERC20(vault.asset()).decimals(),
            18
        );
        contractRegistry.addContractToRegistry(
            keccak256("PerpfiRiskManager"),
            address(perpfiRiskManager)
        );
        contractRegistry.addContractToRegistry(
            keccak256("SnxRiskManager"),
            address(snxRiskManager)
        );
    }

    function registerMarket(
        bytes32 _marketName,
        address _marketAddress,
        address _riskManager,
        address _baseToken,
        address _marginToken
    ) internal {
        marketManager.addMarket(_marketName, _marketAddress, _riskManager, _baseToken, _marginToken);
    }
}
