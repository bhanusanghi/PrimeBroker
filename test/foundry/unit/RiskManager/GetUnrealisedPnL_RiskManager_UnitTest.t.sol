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

contract GetUnrealisedPnL_RiskManager_UnitTest is RiskManager_UnitTest {
    function test_returns_zero_when_invalid_account()
        public
        invalidMarginAccount
    {
        int256 pnlFetched = contracts.riskManager.getUnrealizedPnL(david);
        assertEq(pnlFetched, 0);
    }

    function test_returns_zero_when_zero_pnl() public validMarginAccount {
        int256 pnlFetched = contracts.riskManager.getUnrealizedPnL(
            bobMarginAccount
        );
        assertEq(uint256(pnlFetched), 0);
    }

    function test_returns_sum_same_direction()
        public
        validMarginAccount
        positivePnL
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        int256 pnl = 100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        vm.mockCall(
            address(contracts.snxRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );

        int256 pnlFetched = contracts.riskManager.getUnrealizedPnL(
            bobMarginAccount
        );
        assertEq(uint256(pnlFetched), 200 ether);
    }

    function test_returns_sum_opposite_direction()
        public
        validMarginAccount
        positivePnL
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        int256 pnl = 100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        vm.mockCall(
            address(contracts.snxRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(-200 ether)
        );

        int256 pnlFetched = contracts.riskManager.getUnrealizedPnL(
            bobMarginAccount
        );
        assertEq(pnlFetched, -100 ether);
    }
}
