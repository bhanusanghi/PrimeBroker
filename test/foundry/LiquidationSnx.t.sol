pragma solidity ^0.8.10;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {SnxUtils} from "./utils/SnxUtils.sol";
import {PerpfiUtils} from "./utils/PerpfiUtils.sol";
import {ChronuxUtils, LiquidationParams} from "./utils/ChronuxUtils.sol";
import {IMarginAccount} from "../../contracts/Interfaces/IMarginAccount.sol";
import {Position} from "../../../contracts/Interfaces/IMarginAccount.sol";
import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";
import {ICircuitBreaker} from "../../contracts/Interfaces/SNX/ICircuitBreaker.sol";
import {IExchangeRates} from "../../contracts/Interfaces/SNX/IExchangeRates.sol";
import {IExchangeCircuitBreaker} from "../../contracts/Interfaces/SNX/IExchangeCircuitBreaker.sol";
import {ISystemStatus} from "../../contracts/Interfaces/SNX/ISystemStatus.sol";

contract LiquidationSnx is BaseSetup {
    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    PerpfiUtils perpfiUtils;
    SnxUtils snxUtils;
    ChronuxUtils chronuxUtils;

    function setUp() public {
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            37274241
        );
        vm.selectFork(forkId);
        utils = new Utils();
        setupSNXFixture();
        perpfiUtils = new PerpfiUtils(contracts);
        chronuxUtils = new ChronuxUtils(contracts);
        snxUtils = new SnxUtils(contracts);
    }

    // ChronuxMargin |  Snx Margin | snx ON
    // 1000 USDC     |  0 USDC     | 0 USDC
    // 0 USDC        |  2000 USDC  | 3000 USDC               -> Min Margin = 800
    // 0 USDC        |  2000 USDC  | 2000 USDC               pnl = -1000$ (is liquidatablt true)
    function testIsLiquidatableUnrealisedPnL() public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);

        int256 snxMargin = int256(2000 ether);
        int256 openNotional = int256(3000 ether);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        console2.log("iap", assetPrice);
        int256 positionSize = (openNotional * 1 ether) / assetPrice.toInt256();
        console2.log("positionSize abc", positionSize);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        console2.log("deposited margin snx", positionSize);

        snxUtils.addAndVerifyPosition(bob, snxUniKey, positionSize, false, "");
        console2.log("added position");
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(snxUniKey);
        console2.log("simulating pnl now");
        console2.log("on", openPosition.openNotional);
        console2.log("os", openPosition.size);
        utils.simulateUnrealisedPnLSnx(
            circuitBreaker,
            bobMarginAccount,
            snxUni_marketKey,
            openPosition.openNotional,
            openPosition.size,
            -1000 ether
        );
        (assetPrice, ) = IFuturesMarket(market).assetPrice();
        console2.log("uap", assetPrice);
        (bool isLiquidatable, bool isFullyLiquidatable) = contracts
            .riskManager
            .isAccountLiquidatable(IMarginAccount(bobMarginAccount));

        assertEq(
            isLiquidatable,
            true,
            "IsLiquidatable is not working properly"
        );
        // check third party events and value by using static call.
    }

    // ChronuxMargin |  Snx Margin | snx ON
    // 1000 USDC     |  0 USDC     | 0 USDC
    // 0 USDC        |  2000 USDC  | 3000 USDC               -> Min Margin = 800
    // 0 USDC        |  2000 USDC  | 2000 USDC               pnl = -1000$ (is liquidatablt true)
    function testIsNotLiquidatableWithoutPnL() public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);

        int256 snxMargin = int256(2000 ether);
        int256 openNotional = int256(3000 ether);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 positionSize = (openNotional * 1 ether) / assetPrice.toInt256();
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");

        snxUtils.addAndVerifyPosition(bob, snxUniKey, positionSize, false, "");
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(snxUniKey);

        (assetPrice, ) = IFuturesMarket(market).assetPrice();
        (bool isLiquidatable, bool isFullyLiquidatable) = contracts
            .riskManager
            .isAccountLiquidatable(IMarginAccount(bobMarginAccount));

        assertEq(
            isLiquidatable,
            false,
            "IsLiquidatable is not working properly"
        );
        // check third party events and value by using static call.
    }

    function testIsNotLiquidatableUnrealisedPnl() public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);

        int256 snxMargin = int256(2000 ether);
        int256 openNotional = int256(3000 ether);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 positionSize = (openNotional * 1 ether) / assetPrice.toInt256();
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");

        snxUtils.addAndVerifyPosition(bob, snxUniKey, positionSize, false, "");
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(snxUniKey);

        (assetPrice, ) = IFuturesMarket(market).assetPrice();
        (bool isLiquidatable, bool isFullyLiquidatable) = contracts
            .riskManager
            .isAccountLiquidatable(IMarginAccount(bobMarginAccount));
        utils.simulateUnrealisedPnLSnx(
            circuitBreaker,
            bobMarginAccount,
            snxUni_marketKey,
            openPosition.openNotional,
            openPosition.size,
            -10 ether
        );
        assertEq(
            isLiquidatable,
            false,
            "IsLiquidatable is not working properly"
        );
        // check third party events and value by using static call.
    }

    // ChronuxMargin |  Snx Margin | snx ON
    // 1000 USDC     |  0 USDC     | 0 USDC
    // 0 USDC        |  2000 USDC  | 3000 USDC               -> Min Margin = 600
    function testMinimumMarginRequirement() public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        uint256 minMarginRequirement = contracts
            .riskManager
            .getMinimumMarginRequirement(bobMarginAccount);
        uint256 accountValue = contracts.riskManager.getAccountValue(
            bobMarginAccount
        );
        console2.log("iminMarginRequirement", minMarginRequirement);
        console2.log("iaccountValue", accountValue);
        int256 snxMargin = int256(2000 ether);
        int256 openNotional = int256(3000 ether);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 positionSize = (openNotional * 1 ether) / assetPrice.toInt256();
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");

        snxUtils.addAndVerifyPosition(bob, snxUniKey, positionSize, false, "");
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(snxUniKey);

        minMarginRequirement = contracts
            .riskManager
            .getMinimumMarginRequirement(bobMarginAccount);
        accountValue = contracts.riskManager.getAccountValue(bobMarginAccount);
        console2.log("fminMarginRequirement", minMarginRequirement);
        console2.log("faccountValue", accountValue);
    }

    // ChronuxMargin |  Snx Margin | snx ON
    // 1000 USDC     |  0 USDC     | 0 USDC
    // 0 USDC        |  1000 susd  | 3500 ether               -> Min Margin = 700
    // 0 USDC        |  1000 susd  | 3300 ether                unrealisedPnL = -200
    function testMinimumMarginRequirementWithUnrealisedPnLHighLev() public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);

        int256 snxMargin = int256(1000 ether);
        int256 openNotional = int256(3500 ether);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        console2.log("AssetPrice", assetPrice);
        int256 positionSize = (openNotional * 1 ether) / assetPrice.toInt256();

        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        snxUtils.addAndVerifyPosition(bob, snxUniKey, positionSize, false, "");
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(snxUniKey);
        console2.log("positionSize", positionSize);
        console2.log("ActualpositionSize", openPosition.size);
        console2.log("openNotional", openNotional);
        console2.log("ActualopenNotional", openPosition.openNotional);
        uint256 minMarginRequirement = contracts
            .riskManager
            .getMinimumMarginRequirement(bobMarginAccount);
        uint256 accountValue = contracts.riskManager.getAccountValue(
            bobMarginAccount
        );
        console2.log("iminMarginRequirement", minMarginRequirement);
        console2.log("iaccountValue", accountValue);

        utils.simulateUnrealisedPnLSnx(
            circuitBreaker,
            bobMarginAccount,
            snxUni_marketKey,
            openPosition.openNotional,
            openPosition.size,
            -200 ether
        );
        (assetPrice, ) = IFuturesMarket(market).assetPrice();
        console2.log("finalAssetPrice", assetPrice);
        minMarginRequirement = contracts
            .riskManager
            .getMinimumMarginRequirement(bobMarginAccount);
        accountValue = contracts.riskManager.getAccountValue(bobMarginAccount);
        console2.log("fminMarginRequirement", minMarginRequirement);
        console2.log("faccountValue", accountValue);
    }

    // ChronuxMargin |  Snx Margin | snx ON
    // 1000 USDC     |  0 USDC     | 0 USDC
    // 0 USDC        |  1000 susd  | 2500 ether               -> Min Margin = 500
    // 0 USDC        |  1000 susd  | 2300 ether               unrealisedPnL = -200
    function testMinimumMarginRequirementWithUnrealisedPnLLowLev() public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);

        int256 snxMargin = int256(1000 ether);
        int256 openNotional = int256(2500 ether);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 positionSize = (openNotional * 1 ether) / assetPrice.toInt256();
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        snxUtils.addAndVerifyPosition(bob, snxUniKey, positionSize, false, "");
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(snxUniKey);

        uint256 minMarginRequirement = contracts
            .riskManager
            .getMinimumMarginRequirement(bobMarginAccount);
        uint256 accountValue = contracts.riskManager.getAccountValue(
            bobMarginAccount
        );
        console2.log("iminMarginRequirement", minMarginRequirement);
        console2.log("iaccountValue", accountValue);

        utils.simulateUnrealisedPnLSnx(
            circuitBreaker,
            bobMarginAccount,
            snxUni_marketKey,
            openPosition.openNotional,
            openPosition.size,
            -200 ether
        );

        minMarginRequirement = contracts
            .riskManager
            .getMinimumMarginRequirement(bobMarginAccount);
        accountValue = contracts.riskManager.getAccountValue(bobMarginAccount);
        console2.log("fminMarginRequirement", minMarginRequirement);
        console2.log("faccountValue", accountValue);
    }

    // ChronuxMargin |  Snx Margin | snx ON
    // 1000 USDC     |  0 USDC     | 0 USDC
    // 0 USDC        |  1000 susd  | 2500 ether               -> Min Margin = 500
    // 0 USDC        |  1000 susd  | 2300 ether               unrealisedPnL = -510
    function testLiquidateUnrealisedPnl() public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);

        int256 snxMargin = int256(1000 ether);
        int256 openNotional = int256(2500 ether);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, bool isInvalid) = IFuturesMarket(market)
            .assetPrice();
        int256 positionSize = (openNotional * 1 ether) / assetPrice.toInt256();
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");

        snxUtils.addAndVerifyPosition(bob, snxUniKey, positionSize, false, "");
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(snxUniKey);

        (assetPrice, isInvalid) = IFuturesMarket(market).assetPrice();
        (bool isLiquidatable, bool isFullyLiquidatable) = contracts
            .riskManager
            .isAccountLiquidatable(IMarginAccount(bobMarginAccount));
        (uint rate, bool broken, bool staleOrInvalid) = IExchangeRates(
            exchangeRates
        ).rateWithSafetyChecks(snxUni_marketKey);
        console2.log(rate, "rate");
        console2.log(broken, "broken");
        console2.log(staleOrInvalid, "staleOrInvalid");
        // vm.warp(block.timestamp + 10);
        utils.simulateUnrealisedPnLSnx(
            circuitBreaker,
            bobMarginAccount,
            snxUni_marketKey,
            openPosition.openNotional,
            openPosition.size,
            -510 ether
        );
        (assetPrice, isInvalid) = IFuturesMarket(market).assetPrice();

        (rate, broken, staleOrInvalid) = IExchangeRates(exchangeRates)
            .rateWithSafetyChecks(snxUni_marketKey);

        bool suspended = ISystemStatus(systemStatus).synthSuspended(
            snxUni_marketKey
        );
        console2.log(suspended, "suspended");
        // bool breakHuaKya  = ICircuitBreaker(circuitBreaker)
        //     .probeCircuitBreaker(snxUni_marketKey);
        // vm.mockCall(
        //     exchangeCircuitBreaker,
        //     abi.encodeWithSelector(
        //         IExchangeCircuitBreaker.rateWithBreakCircuit.selector
        //     ),
        //     abi.encode(rate, false)
        // )
        // console2.log(rote, "rote");
        // console2.log(isBroken, "fisBroken");
        console2.log(rate, "frate");
        console2.log(broken, "fbroken");
        console2.log(staleOrInvalid, "fstaleOrInvalid");

        assertEq(
            isLiquidatable,
            false,
            "IsLiquidatable is not working properly"
        );
        LiquidationParams memory params = chronuxUtils.getLiquidationData(bob);
        contracts.marginManager.liquidate(
            bob,
            params.activeMarkets,
            params.destinations,
            params.data
        );
        // check third party events and value by using static call.
    }
}
