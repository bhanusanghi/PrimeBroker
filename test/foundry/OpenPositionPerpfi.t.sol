pragma solidity ^0.8.10;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
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
contract OpenPositionPerpfi is BaseSetup {
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
        chronuxUtils = new ChronuxUtils(contracts);
        perpfiUtils = new PerpfiUtils(contractsÏ);
    }

    // Internal
    function testMarginTransferPerp(int256 perpMargin) public {
        uint256 chronuxMargin = 500 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        uint256 marginFactor = contracts.riskManager.initialMarginFactor();
        int256 expectedRemainingMargin = int256(
            (chronuxMargin * 100) / marginFactor
        );
        // vm.assume(
        //     perpMargin > int256(1 * ONE_USDC) &&
        //         perpMargin < expectedRemainingMargin
        // );
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            1000_000000,
            false,
            ""
        );
    }

    function testExcessMarginTransferRevert(int256 perpMargin) public {
        uint256 chronuxMargin = 500 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        uint256 marginFactor = contracts.riskManager.initialMarginFactor();
        int256 expectedRemainingMargin = int256(
            (chronuxMargin * 100) / marginFactor
        );
        vm.assume(
            perpMargin > expectedRemainingMargin &&
                perpMargin < 2 * expectedRemainingMargin
        );
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            true,
            "Borrow limit exceeded"
        );
    }

    function testOpenPositionPerpExtraLeverageRevert(int256 notional) public {
        uint256 chronuxMargin = 500 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        int256 perpMarginFactor = 10;
        int256 perpMargin = int256(1000 * ONE_USDC);

        int256 expectedRemainingNotional = int256(
            contracts.riskManager.getRemainingPositionOpenNotional(
                bobMarginAccount
            )
        );

        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        vm.assume(
            notional > expectedRemainingNotional &&
                notional < 2 * expectedRemainingNotional
        );
        perpfiUtils.addAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            -notional,
            true,
            "Extra leverage not allowed"
        );
    }

    function testOpenShortPositionWithNotionalPerp(int256 notional) public {
        uint256 chronuxMargin = 500 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        int256 perpMarginFactor = 10;
        int256 perpMargin = int256(1000 * ONE_USDC);

        int256 expectedRemainingNotional = int256(
            contracts.riskManager.getRemainingPositionOpenNotional(
                bobMarginAccount
            )
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
        // check third party events and value by using static call.
    }

    function testOpenShortPositionWithSizePerp(int256 size) public {
        uint256 chronuxMargin = 500 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        int256 perpMarginFactor = 10;
        int256 perpMargin = int256(1000 * ONE_USDC);

        int256 expectedRemainingNotional = int256(
            contracts.riskManager.getRemainingPositionOpenNotional(
                bobMarginAccount
            )
        );
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        uint256 markPrice = utils.getMarkPricePerp(
            perpMarketRegistry,
            perpAaveMarket
        );
        uint256 maxSize = uint256(expectedRemainingNotional) / markPrice;

        vm.assume(size > 1 ether && size < int256(maxSize));
        perpfiUtils.addAndVerifyPositionSize(
            bob,
            perpAaveKey,
            -size,
            false,
            ""
        );
        // check third party events and value by using static call.
    }

    function testOpenLongPositionWithSizePerp(int256 size) public {
        uint256 chronuxMargin = 500 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        int256 perpMarginFactor = 10;
        int256 perpMargin = int256(1000 * ONE_USDC);

        int256 expectedRemainingNotional = int256(
            contracts.riskManager.getRemainingPositionOpenNotional(
                bobMarginAccount
            )
        );
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        uint256 markPrice = utils.getMarkPricePerp(
            perpMarketRegistry,
            perpAaveMarket
        );
        uint256 maxSize = uint256(expectedRemainingNotional) / markPrice;

        vm.assume(size > 1 ether && size < int256(maxSize));
        perpfiUtils.addAndVerifyPositionSize(bob, perpAaveKey, size, false, "");
        // check third party events and value by using static call.
    }

    function testOpenLongPositionWithNotionalPerp(int256 notional) public {
        uint256 chronuxMargin = 500 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        int256 perpMarginFactor = 10;
        int256 perpMargin = int256(1000 * ONE_USDC);

        int256 expectedRemainingNotional = int256(
            contracts.riskManager.getRemainingPositionOpenNotional(
                bobMarginAccount
            )
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

        // check third party events and value by using static call.
    }

    function testLongWithdrawCollateral() public {
        int256 notional = 5000 ether;
        uint256 chronuxMargin = 1500 * ONE_USDC;
        int256 perpMargin = int256(1200 * ONE_USDC);
        uint256 withdrawAmount = 250 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);

        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        perpfiUtils.addAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );
        uint256 _beforeBalance = IERC20(contracts.vault.asset()).balanceOf(
            bobMarginAccount
        );
        uint256 _beforeBobBalance = IERC20(contracts.vault.asset()).balanceOf(
            bob
        );
        vm.startPrank(bob);
        contracts.collateralManager.withdrawCollateral(
            contracts.vault.asset(),
            withdrawAmount
        );
        vm.stopPrank();
        assertEq(
            IERC20(contracts.vault.asset()).balanceOf(bob),
            _beforeBobBalance + withdrawAmount
        );
        assertEq(
            IERC20(contracts.vault.asset()).balanceOf(bobMarginAccount),
            _beforeBalance - withdrawAmount
        );
    }
}
