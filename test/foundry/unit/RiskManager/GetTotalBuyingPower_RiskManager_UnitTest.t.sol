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

contract GetTotalBuyingPower_RiskManager_UnitTest is RiskManager_UnitTest {
    function test_Zero_BuyingPower_When_InvalidMarginAccount()
        public
        invalidMarginAccount
    {
        uint256 bp = contracts.riskManager.getTotalBuyingPower(david);
        assertEq(bp, 0);
        bp = contracts.riskManager.getTotalBuyingPower(
            contracts.contractWithFallback
        );
        assertEq(bp, 0);
        bp = contracts.riskManager.getTotalBuyingPower(
            contracts.contractWithoutFallback
        );
        assertEq(bp, 0);
    }

    function test_zero_bp_when_0_collateral() public zeroCollateral {
        uint256 bp = contracts.riskManager.getTotalBuyingPower(
            bobMarginAccount
        );
        assertEq(bp, 0);
    }

    function test_bp_with_interest()
        public
        nonZeroCollateral
        hasInterestAccrued
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        uint256 interestX18 = 100 ether;
        vm.mockCall(
            bobMarginAccount,
            abi.encodeWithSelector(
                IMarginAccount.getInterestAccruedX18.selector
            ),
            abi.encode(interestX18)
        );
        uint256 bp = contracts.riskManager.getTotalBuyingPower(
            bobMarginAccount
        );
        assertEq(bp, (1000 - 100) * 4 ether);
    }

    function test_bp_with_positive_unrealised_pnl()
        public
        nonZeroCollateral
        zeroInterestAccrued
        hasUnrealisedPnL
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
        uint256 bp = contracts.riskManager.getTotalBuyingPower(
            bobMarginAccount
        );
        assertEq(bp, (1000 + 100) * 4 ether);
    }

    function test_bp_with_negative_unrealised_pnl()
        public
        nonZeroCollateral
        zeroInterestAccrued
        hasUnrealisedPnL
        negativePnL
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        int256 pnl = 100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(-pnl)
        );
        uint256 bp = contracts.riskManager.getTotalBuyingPower(
            bobMarginAccount
        );
        assertEq(bp, (1000 - 100) * 4 ether);
    }

    function test_bp_with_interest_and_negative_unrealised_pnl()
        public
        nonZeroCollateral
        hasInterestAccrued
        hasUnrealisedPnL
        negativePnL
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        int256 pnl = 100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(-pnl)
        );
        uint256 interestX18 = 100 ether;
        vm.mockCall(
            bobMarginAccount,
            abi.encodeWithSelector(
                IMarginAccount.getInterestAccruedX18.selector
            ),
            abi.encode(interestX18)
        );
        uint256 bp = contracts.riskManager.getTotalBuyingPower(
            bobMarginAccount
        );
        assertEq(bp, (1000 - 100 - 100) * 4 ether);
    }

    function test_bp_with_interest_and_positive_unrealised_pnl()
        public
        nonZeroCollateral
        hasInterestAccrued
        hasUnrealisedPnL
        positivePnL
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        int256 pnl = 220 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        uint256 interestX18 = 100 ether;
        vm.mockCall(
            bobMarginAccount,
            abi.encodeWithSelector(
                IMarginAccount.getInterestAccruedX18.selector
            ),
            abi.encode(interestX18)
        );
        uint256 bp = contracts.riskManager.getTotalBuyingPower(
            bobMarginAccount
        );
        assertEq(bp, (1000 - 100 + 220) * 4 ether);
    }

    function test_negative_tcv()
        public
        nonZeroCollateral
        hasInterestAccrued
        hasUnrealisedPnL
        positivePnL
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        int256 pnl = 20 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        uint256 interestX18 = 1200 ether;
        vm.mockCall(
            bobMarginAccount,
            abi.encodeWithSelector(
                IMarginAccount.getInterestAccruedX18.selector
            ),
            abi.encode(interestX18)
        );
        uint256 bp = contracts.riskManager.getTotalBuyingPower(
            bobMarginAccount
        );
        assertEq(bp, 0);
    }

    function test_negative_tcv_with_negative_pnl()
        public
        nonZeroCollateral
        hasInterestAccrued
        hasUnrealisedPnL
        positivePnL
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        int256 pnl = -2000 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        vm.mockCall(
            bobMarginAccount,
            abi.encodeWithSelector(
                IMarginAccount.getInterestAccruedX18.selector
            ),
            abi.encode(0)
        );
        uint256 bp = contracts.riskManager.getTotalBuyingPower(
            bobMarginAccount
        );
        assertEq(bp, 0);
    }
}
