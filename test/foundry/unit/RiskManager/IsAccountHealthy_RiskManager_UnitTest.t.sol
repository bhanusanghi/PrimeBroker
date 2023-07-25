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

contract Is_Account_Healthy_RiskManager_UnitTest is RiskManager_UnitTest {
    function test_is_Account_Healthy_returns_true_when_invalid_account()
        public
        invalidMarginAccount
    {
        bool isHealthy = contracts.riskManager.isAccountHealthy(david);
        assertEq(isHealthy, true);
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

    function test_is_Account_Healthy_returns_true_when_enough_margin()
        public
        validMarginAccount
        nonZeroCollateral
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
}
