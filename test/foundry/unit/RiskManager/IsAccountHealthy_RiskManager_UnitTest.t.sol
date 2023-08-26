pragma solidity ^0.8.10;

import "forge-std/console2.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SettlementTokenMath} from "../../../../contracts/Libraries/SettlementTokenMath.sol";
import {BaseSetup} from "../../BaseSetup.sol";
import {RiskManager_UnitTest} from "./RiskManager_UnitTest.t.sol";
import {IMarginAccount, Position} from "../../../../contracts/Interfaces/IMarginAccount.sol";
import {IProtocolRiskManager} from "../../../../contracts/Interfaces/IProtocolRiskManager.sol";
import {IRiskManager, VerifyLiquidationResult} from "../../../../contracts/Interfaces/IRiskManager.sol";

contract IsAccountHealthy_RiskManager_UnitTest is RiskManager_UnitTest {
    function test_is_Account_Healthy_returns_true_when_invalid_account()
        public
        invalidMarginAccount
    {
        vm.expectRevert();
        bool isHealthy = contracts.riskManager.isAccountHealthy(david);
    }

    function test_is_Account_Healthy_returns_true_when_no_collateral()
        public
        validMarginAccount
        zeroCollateral
    {
        bool isHealthy = contracts.riskManager.isAccountHealthy(
            bobMarginAccount
        );
        assertEq(isHealthy, true);
    }

    function test_is_Account_Healthy_returns_true_when_no_open_positions()
        public
        validMarginAccount
        nonZeroCollateral
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        bool isHealthy = contracts.riskManager.isAccountHealthy(
            bobMarginAccount
        );
        assertEq(isHealthy, true);
    }

    function test_is_Account_Healthy_returns_true_when_margin_in_TPP()
        public
        validMarginAccount
        nonZeroCollateral
        marginInTPP
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            1000 * 1e6,
            false,
            ""
        );
        bool isHealthy = contracts.riskManager.isAccountHealthy(
            bobMarginAccount
        );
        assertEq(isHealthy, true);
    }

    function test_is_Account_Healthy_result_when_low_margin()
        public
        validMarginAccount
        negativePnL
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            1000 * 1e6,
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            3900 ether,
            false,
            ""
        );
        int256 pnl = -100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        vm.prank(address(contracts.marginManager));
        bool isHealthy = contracts.riskManager.isAccountHealthy(
            bobMarginAccount
        );
        assertEq(isHealthy, false);
    }

    function test_adding_enough_collateral_in_unhealhty_account()
        public
        validMarginAccount
        negativePnL
        depositCollateral
        finallyHealthy
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            1000 * 1e6,
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            3900 ether,
            false,
            ""
        );
        int256 pnl = -100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        vm.prank(address(contracts.marginManager));
        bool isHealthy = contracts.riskManager.isAccountHealthy(
            bobMarginAccount
        );
        assertEq(isHealthy, false);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 100 * 1e6);
        isHealthy = contracts.riskManager.isAccountHealthy(bobMarginAccount);
        assertEq(isHealthy, true);
    }

    function test_adding_insufficient_collateral_in_unhealhty_account()
        public
        validMarginAccount
        negativePnL
        depositCollateral
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            1000 * 1e6,
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            3900 ether,
            false,
            ""
        );
        int256 pnl = -100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        vm.prank(address(contracts.marginManager));
        bool isHealthy = contracts.riskManager.isAccountHealthy(
            bobMarginAccount
        );
        assertEq(isHealthy, false);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1 * 1e6);
        isHealthy = contracts.riskManager.isAccountHealthy(bobMarginAccount);
        assertEq(isHealthy, false);
    }

    function test_reducing_sufficient_notional_in_unhealthy_account()
        public
        validMarginAccount
        negativePnL
        reducedNotional
        finallyHealthy
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            1000 * 1e6,
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            3900 ether,
            false,
            ""
        );
        int256 pnl = -100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        vm.prank(address(contracts.marginManager));
        bool isHealthy = contracts.riskManager.isAccountHealthy(
            bobMarginAccount
        );
        assertEq(isHealthy, false);
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            -900 ether,
            false,
            ""
        );
        isHealthy = contracts.riskManager.isAccountHealthy(bobMarginAccount);
        assertEq(isHealthy, true);
    }

    function test_reducing_insufficient_notional_in_unhealthy_account()
        public
        validMarginAccount
        negativePnL
        reducedNotional
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            1000 * 1e6,
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            3900 ether,
            false,
            ""
        );
        int256 pnl = -100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        vm.prank(address(contracts.marginManager));
        bool isHealthy = contracts.riskManager.isAccountHealthy(
            bobMarginAccount
        );
        assertEq(isHealthy, false);
        vm.expectRevert("MM: Unhealthy account");
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            -9 ether,
            false,
            ""
        );
    }

    function test_closing_position_in_unhealthy_account()
        public
        validMarginAccount
        negativePnL
        reducedNotional
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            1000 * 1e6,
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            3900 ether,
            false,
            ""
        );
        int256 pnl = -100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        vm.prank(address(contracts.marginManager));
        bool isHealthy = contracts.riskManager.isAccountHealthy(
            bobMarginAccount
        );
        assertEq(isHealthy, false);
        perpfiUtils.closeAndVerifyPosition(bob, perpAaveKey);
        isHealthy = contracts.riskManager.isAccountHealthy(bobMarginAccount);
        assertEq(isHealthy, true);
    }
}
