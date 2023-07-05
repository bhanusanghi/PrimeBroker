pragma solidity ^0.8.10;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {SnxUtils} from "./utils/SnxUtils.sol";
import {PerpfiUtils} from "./utils/PerpfiUtils.sol";
import {ChronuxUtils, LiquidationParams} from "./utils/ChronuxUtils.sol";
import {IMarginAccount, Position} from "../../contracts/Interfaces/IMarginAccount.sol";
import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";
import {ICircuitBreaker} from "../../contracts/Interfaces/SNX/ICircuitBreaker.sol";
import {IExchangeRates} from "../../contracts/Interfaces/SNX/IExchangeRates.sol";
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
        setupPerpfiFixture();
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
        int256 positionSize = (openNotional * 1 ether) / assetPrice.toInt256();
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        snxUtils.addAndVerifyPosition(bob, snxUniKey, positionSize, false, "");
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(snxUniKey);
        utils.simulateUnrealisedPnLSnx(
            circuitBreaker,
            bobMarginAccount,
            snxUni_marketKey,
            openPosition.openNotional,
            openPosition.size,
            -1000 ether
        );
        (assetPrice, ) = IFuturesMarket(market).assetPrice();
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
        utils.simulateUnrealisedPnLSnx(
            circuitBreaker,
            bobMarginAccount,
            snxUni_marketKey,
            openPosition.openNotional,
            openPosition.size,
            -200 ether
        );
        (assetPrice, ) = IFuturesMarket(market).assetPrice();
        minMarginRequirement = contracts
            .riskManager
            .getMinimumMarginRequirement(bobMarginAccount);
        accountValue = contracts.riskManager.getAccountValue(bobMarginAccount);
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
    }

    // ChronuxMargin |  Snx Margin | snx ON
    // 1000 USDC     |  0 USDC     | 0 USDC
    // 0 USDC        |  1000 susd  | 2500 ether               -> Min Margin = 500
    // 0 USDC        |  1000 susd  | 2300 ether               unrealisedPnL = -510
    // 451.9 USDC    |  0 susd     | 0 ether                   realizedPnL = -548.1
    function testLiquidateUnrealisedPnl() public {
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
        (int256 notionalOnSnx, ) = IFuturesMarket(market).notionalValue(
            bobMarginAccount
        );
        utils.simulateUnrealisedPnLSnx(
            circuitBreaker,
            bobMarginAccount,
            snxUni_marketKey,
            openPosition.openNotional,
            openPosition.size,
            -510 ether
        );
        (notionalOnSnx, ) = IFuturesMarket(market).notionalValue(
            bobMarginAccount
        );
        LiquidationParams memory params = chronuxUtils.getLiquidationData(bob);
        contracts.marginManager.liquidate(
            bob,
            params.activeMarkets,
            params.destinations,
            params.data
        );
        (notionalOnSnx, ) = IFuturesMarket(market).notionalValue(
            bobMarginAccount
        );
    }

    // ChronuxMargin |  Snx Margin | snx ON        | Perp Margin | perp ON
    // 1000 USDC     |  0 USDC     | 0 USDC        |  0 USDC     | 0 USDC
    // 0 USDC        |  1000 susd  | 2500 ether    |  0 susd     | 0 ether             Min Margin = 500
    // 0 USDC        |  1000 susd  | 2500 ether    |  500 usdc   | 500 ether           Min Margin = 600
    // 0 USDC        |  1000 susd  | 1990 ether    |  0 usdc     | 520 ether           unrealisedPnL = -510 + 20
    // 451.9 USDC    |  0 susd     | 0 ether       |  0 usdc     | 0 ether             realizedPnL = -548.1
    function testLiquidateUnrealisedPnlSnXPerpfi() public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        int256 snxMargin = int256(1000 ether);
        int256 perpMargin = int256(1000 * 10 ** 6);
        int256 openNotional = int256(2500 ether);
        int256 openNotional2 = int256(500 ether);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 positionSize = (openNotional * 1 ether) / assetPrice.toInt256();
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );

        snxUtils.addAndVerifyPosition(bob, snxUniKey, positionSize, false, "");
        perpfiUtils.addAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            openNotional2,
            false,
            ""
        );
        Position memory snxPosition = IMarginAccount(bobMarginAccount)
            .getPosition(snxUniKey);
        Position memory perpPosition = IMarginAccount(bobMarginAccount)
            .getPosition(perpAaveKey);
        utils.simulateUnrealisedPnLSnx(
            circuitBreaker,
            bobMarginAccount,
            snxUni_marketKey,
            snxPosition.openNotional,
            snxPosition.size,
            -600 ether
        );
        utils.simulateUnrealisedPnLPerpfi(
            perpAccountBalance,
            bobMarginAccount,
            perpAaveMarket,
            perpPosition.openNotional,
            perpPosition.size,
            20 ether
        );
        LiquidationParams memory params = chronuxUtils.getLiquidationData(bob);
        contracts.marginManager.liquidate(
            bob,
            params.activeMarkets,
            params.destinations,
            params.data
        );

        snxPosition = IMarginAccount(bobMarginAccount).getPosition(snxUniKey);
        perpPosition = IMarginAccount(bobMarginAccount).getPosition(
            perpAaveKey
        );
        assertEq(
            IMarginAccount(bobMarginAccount).existingPosition(snxUniKey),
            false
        );
        assertEq(
            IMarginAccount(bobMarginAccount).existingPosition(perpAaveKey),
            false
        );
        assertEq(snxPosition.size, 0, "position after liquidation is not zero");
        assertEq(
            perpPosition.size,
            0,
            "position after liquidation is not zero"
        );
        assertEq(
            snxPosition.openNotional,
            0,
            "position after liquidation is not zero"
        );
        assertEq(
            perpPosition.openNotional,
            0,
            "position after liquidation is not zero"
        );
        // TODO -> ADD repay
        assertEq(
            IMarginAccount(bobMarginAccount).totalBorrowed(),
            0,
            "totalBorrowed after liquidation is not zero"
        );
        assertEq(
            contracts.riskManager.getCurrentDollarMarginInMarkets(
                bobMarginAccount
            ),
            0,
            "totalDollarMarginInMarkets after liquidation is not zero"
        );
        assertEq(
            ERC20(susd).balanceOf(bobMarginAccount),
            0,
            "susd balance is not zero"
        );
        // assertEq(
        //     IMarginAccount(bobMarginAccount).totalBorrowed(),
        //     0,
        //     "totalBorrowed after liquidation is not zero"
        // );

        assertEq(
            IMarginAccount(bobMarginAccount).getTotalOpeningAbsoluteNotional(),
            0,
            "getTotalOpeningAbsoluteNotional after liquidation is not zero"
        );
        console2.log(
            "remainingMargin",
            contracts.collateralManager.getFreeCollateralValue(bobMarginAccount)
        );
    }

    // Vault interest rate -> 5% per annum
    // ChronuxMargin |  Snx Margin | snx ON
    // 1000 USDC     |  0 USDC     | 0 USDC
    // 0 USDC        |  2000 susd  | 3000 ether               -> Min Margin = 600
    // warp(3600 * 24 * 7); // warp week
    // interest accrued
    // 0 USDC        |  2000 susd  | 2399 ether               unrealisedPnL = -601
    // 451.9 USDC    |  0 susd     | 0 ether                   realizedPnL =
    function testLiquidateUnrealisedPnlWithInterestAccrued() public {
        // set vault interest rate
        // utils.setVaultInterestRateRay(address(contracts.vault), 5);
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        int256 snxMargin = int256(2000 ether);
        int256 openNotional = int256(2500 ether);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 positionSize = (openNotional * 1 ether) / assetPrice.toInt256();
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");

        snxUtils.addAndVerifyPosition(bob, snxUniKey, positionSize, false, "");
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(snxUniKey);
        (int256 notionalOnSnx, ) = IFuturesMarket(market).notionalValue(
            bobMarginAccount
        );
        utils.mineBlocks(365 days, 365 days);
        utils.simulateUnrealisedPnLSnx(
            circuitBreaker,
            bobMarginAccount,
            snxUni_marketKey,
            openPosition.openNotional,
            openPosition.size,
            -510 ether
        );
        (notionalOnSnx, ) = IFuturesMarket(market).notionalValue(
            bobMarginAccount
        );
        LiquidationParams memory params = chronuxUtils.getLiquidationData(bob);
        contracts.marginManager.liquidate(
            bob,
            params.activeMarkets,
            params.destinations,
            params.data
        );
        (notionalOnSnx, ) = IFuturesMarket(market).notionalValue(
            bobMarginAccount
        );
        uint256 accountValue = contracts.riskManager.getAccountValue(
            bobMarginAccount
        );
        uint256 susdBal = ERC20(susd).balanceOf(bobMarginAccount);
        uint256 usdcBal = ERC20(usdc).balanceOf(bobMarginAccount);
        uint256 vaultUsdcBal = ERC20(usdc).balanceOf(address(contracts.vault));
    }
}
