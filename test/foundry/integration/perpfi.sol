pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {BaseSetup} from "../BaseSetup.sol";
import {Utils} from "../utils/Utils.sol";
import {PerpfiUtils} from "../utils/PerpfiUtils.sol";
import {ChronuxUtils} from "../utils/ChronuxUtils.sol";
import {IMarginAccount, Position} from "../../../contracts/Interfaces/IMarginAccount.sol";
import {IClearingHouseConfig} from "../../../contracts/Interfaces/Perpfi/IClearingHouseConfig.sol";
import {IAccountBalance} from "../../../contracts/Interfaces/Perpfi/IAccountBalance.sol";
import {IBaseToken} from "../../../contracts/Interfaces/Perpfi/IBaseToken.sol";

// import {IOrderBook} from "../../../contracts/Interfaces/Perpfi/IOrderBook.sol";

contract PerpfiIntegration is BaseSetup {
    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    PerpfiUtils perpfiUtils;
    ChronuxUtils chronuxUtils;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("ARCHIVE_NODE_URL_L2"), 37274241);
        vm.selectFork(forkId);
        utils = new Utils();
        setupPrmFixture();
        chronuxUtils = new ChronuxUtils(contracts);
        perpfiUtils = new PerpfiUtils(contracts);
    }

    function testMarginInMarket(uint256 margin) public {
        uint256 chronuxMargin = 5000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        vm.assume(margin > 0 && margin < 20000);
        int256 perpMargin = int256(margin * ONE_USDC);
        perpfiUtils.updateAndVerifyMargin(bob, perpAaveKey, perpMargin, false, "");
        int256 expectedMargin = perpMargin;
        int256 expectedMarginValueX18 = contracts.priceOracle.convertToUSD(perpMargin, usdc) * 10 ** 12;
        int256 marginFromChronux = contracts.perpfiRiskManager.getDollarMarginInMarkets(bobMarginAccount);
        int256 marginTpp = perpfiUtils.fetchMargin(bobMarginAccount, perpAaveKey);
        assertEq(expectedMarginValueX18, marginFromChronux);
        assertEq(expectedMargin, marginTpp);
    }

    function testPositionSize(int256 positionSize) public {
        uint256 chronuxMargin = 5000 * ONE_USDC;
        uint256 perpMargin = 4000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        perpfiUtils.updateAndVerifyMargin(bob, perpAaveKey, int256(perpMargin), false, "");
        vm.assume(positionSize > 1 ether && positionSize < 500 ether); // safely assuming position size in range when aave = ~70$
        perpfiUtils.updateAndVerifyPositionSize(bob, perpAaveKey, positionSize, false, "");
        (int256 perpPositionSize, int256 perpPositionOpenNotional) =
            perpfiUtils.fetchPosition(bobMarginAccount, perpAaveKey);
        Position memory position = contracts.riskManager.getMarketPosition(bobMarginAccount, perpAaveKey);
        assertEq(positionSize, perpPositionSize);
        assertEq(positionSize, position.size);
    }

    function testPositionNotional(int256 positionNotional) public {
        uint256 chronuxMargin = 5000 * ONE_USDC;
        uint256 perpMargin = 4000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        perpfiUtils.updateAndVerifyMargin(bob, perpAaveKey, int256(perpMargin), false, "");

        vm.assume(positionNotional > 1 ether && positionNotional < 16000 ether); // safely assuming position size in range when aave = ~90$
        perpfiUtils.updateAndVerifyPositionNotional(bob, perpAaveKey, positionNotional, false, "");
        (int256 perpPositionSize, int256 perpPositionNotional) =
            perpfiUtils.fetchPosition(bobMarginAccount, perpAaveKey);
        Position memory position = contracts.riskManager.getMarketPosition(bobMarginAccount, perpAaveKey);
        assertEq(positionNotional, perpPositionNotional);
        assertEq(positionNotional, position.openNotional);
    }

    function testPositionOrderFee() public {
        uint256 chronuxMargin = 5000 * ONE_USDC;
        uint256 perpMargin = 4000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        perpfiUtils.updateAndVerifyMargin(bob, perpAaveKey, int256(perpMargin), false, "");
        uint256 markPrice1 = perpfiUtils.getMarkPrice(perpExchange, perpMarketRegistry, perpAaveMarket);
        perpfiUtils.updateAndVerifyPositionNotional(bob, perpAaveKey, 2000 ether, false, "");
        perpfiUtils.closeAndVerifyPosition(bob, perpAaveKey);

        // console2.log("abc");
        // // no time travel hence only order fee in unrealisedPnL
        int256 unrealisedPnL = contracts.perpfiRiskManager.getUnrealizedPnL(bobMarginAccount);
        uint256 twoXfee = unrealisedPnL.abs();
        uint256 approx2xFee = 4 ether; //0.1 % of 2000 twice
        assertApproxEqAbs(twoXfee, approx2xFee, 0.1 ether, "Order fee does not match");
    }

    // To be done with time travel testing
    function testFundingRate() public {}

    // owedRealised will have order fee
    function testUnrealisedPnL(int256 openNotional) public {
        uint256 chronuxMargin = 5000 * ONE_USDC;
        uint256 perpMargin = 4000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        perpfiUtils.updateAndVerifyMargin(bob, perpAaveKey, int256(perpMargin), false, "");
        vm.assume(openNotional > 1 ether && openNotional < 3000 ether); // safely assuming position size in range when aave = ~90$
        perpfiUtils.updateAndVerifyPositionNotional(bob, perpAaveKey, openNotional, false, "");
        // 4 hours later
        utils.mineBlocks(4 hours, 4 hours);
        int256 unrealisedPnL = contracts.perpfiRiskManager.getUnrealizedPnL(bobMarginAccount);
        (int256 owedRealizedPnl, int256 unrealizedPnl, uint256 pendingFee) =
            IAccountBalance(perpAccountBalance).getPnlAndPendingFee(bobMarginAccount);
        assertEq(unrealisedPnL, owedRealizedPnl + unrealizedPnl + int256(pendingFee), "Unrealised PnL does not match");
    }

    // factors -> updating is already being verified in util function, liquidation on tpp
    function testPositionStatus() public {
        uint256 chronuxMargin = 5000 * ONE_USDC;
        uint256 perpMargin = 400 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        perpfiUtils.updateAndVerifyMargin(bob, perpAaveKey, int256(perpMargin), false, "");
        perpfiUtils.updateAndVerifyPositionNotional(bob, perpAaveKey, 2000 ether, false, "");
        // before liquidation

        // after liquidation
    }

    // realised pnl is updated in margin in market.
    function testRealisedPnL() public {}
}
