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
import {PerpfiUtils} from "./utils/PerpfiUtils.sol";
import {ChronuxUtils} from "./utils/ChronuxUtils.sol";

/**
 * setup
 * Open position
 * margin and leverage min max fuzzy
 * fee
 * update
 * multiple markets
 * liquidate perpfi
 * liquidate on GB
 * close positions
 * pnl
 * pnl with ranges and multiple positions
 */
contract UpdatePositionPerpfi is BaseSetup {
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
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            37274241
        );
        vm.selectFork(forkId);
        utils = new Utils();
        setupPerpfiFixture();
        perpfiUtils = new PerpfiUtils(contracts);
        chronuxUtils = new ChronuxUtils(contracts);
    }

    // Internal
    function testMarginTransferPerp(int256 perpMargin) public {
        uint256 chronuxMargin = 5000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        uint256 marginFactor = contracts.riskManager.initialMarginFactor();
        int256 expectedRemainingMargin = int256((chronuxMargin * 100) / marginFactor);
        vm.assume(
            perpMargin > int256(1 * ONE_USDC) && perpMargin < expectedRemainingMargin
        );
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            true,
            bytes("Extra transfer not allowed")
        );
    }

    function testOpenShortAndShort(int256 notional) public {
        uint256 chronuxMargin = 5000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        int256 perpMarginFactor = 10;
        int256 perpMargin = int256(10000 * ONE_USDC);

        int256 maxPerpNotional = int256((perpMargin * 100) /
            perpMarginFactor.convertTokenDecimals(6, 18));
        int256 maxChronuxNotional = int256((chronuxMargin * 100) /
            contracts.riskManager.initialMarginFactor());

        int256 expectedRemainingNotional = maxPerpNotional.max(
            maxChronuxNotional
        );
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        vm.assume(notional > 1 ether && notional < expectedRemainingNotional);
        perpfiUtils.addAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            -notional,
            false,
            ""
        );

        chronuxUtils.verifyRemainingPositionNotional(
            bob,
            maxChronuxNotional - notional
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            -(expectedRemainingNotional - notional),
            false,
            ""
        );
        chronuxUtils.verifyRemainingPositionNotional(bob, 0);
        // check third party events and value by using static call.
    }

    function testOpenShortAndLong(int256 notional) public {
        uint256 chronuxMargin = 5000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        int256 perpMarginFactor = 10;
        int256 perpMargin = int256(10000 * ONE_USDC);

        int256 maxPerpNotional = int256((perpMargin * 100) /
            perpMarginFactor.convertTokenDecimals(6, 18));
        int256 maxChronuxNotional = int256((chronuxMargin * 100) /
            contracts.riskManager.initialMarginFactor());

        int256 expectedRemainingNotional = maxPerpNotional.max(
            maxChronuxNotional
        );
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        vm.assume(notional > 1 ether && notional < expectedRemainingNotional);
        perpfiUtils.addAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            -notional,
            false,
            ""
        );

        chronuxUtils.verifyRemainingPositionNotional(
            bob,
            maxChronuxNotional - notional
        );

        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );
        chronuxUtils.verifyRemainingPositionNotional(bob, maxChronuxNotional);
        // check third party events and value by using static call.
    }

    function testOpenLongAndShort(int256 notional) public {
        uint256 chronuxMargin = 5000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        int256 perpMarginFactor = 10;
        int256 perpMargin = int256(10000 * ONE_USDC);

        int256 maxPerpNotional = int256((perpMargin * 100) /
            perpMarginFactor.convertTokenDecimals(6, 18));
        int256 maxChronuxNotional = int256((chronuxMargin * 100) /
            contracts.riskManager.initialMarginFactor());

        int256 expectedRemainingNotional = maxPerpNotional.max(
            maxChronuxNotional
        );
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        vm.assume(notional > 1 ether && notional < expectedRemainingNotional);
        perpfiUtils.addAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );

        chronuxUtils.verifyRemainingPositionNotional(
            bob,
            maxChronuxNotional - notional
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            -notional,
            false,
            ""
        );
        chronuxUtils.verifyRemainingPositionNotional(bob, maxChronuxNotional);
        // check third party events and value by using static call.
    }

    function testOpenLongAndLong(int256 notional) public {
        uint256 chronuxMargin = 5000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        int256 perpMarginFactor = 10;
        int256 perpMargin = int256(10000 * ONE_USDC);

        int256 maxPerpNotional = int256((perpMargin * 100) /
            perpMarginFactor.convertTokenDecimals(6, 18));
        int256 maxChronuxNotional = int256((chronuxMargin * 100) /
            contracts.riskManager.initialMarginFactor());

        int256 expectedRemainingNotional = maxPerpNotional.max(
            maxChronuxNotional
        );
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        vm.assume(notional > 1 ether && notional < expectedRemainingNotional);
        perpfiUtils.addAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );

        chronuxUtils.verifyRemainingPositionNotional(
            bob,
            maxChronuxNotional - notional
        );
        // check third party events and value by using static call.
    }
}
