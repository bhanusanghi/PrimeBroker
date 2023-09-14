pragma solidity ^0.8.10;

import "forge-std/console2.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SettlementTokenMath} from "../../../../contracts/Libraries/SettlementTokenMath.sol";
import {BaseSetup} from "../../BaseSetup.sol";
import {MarginManager_UnitTest} from "./MarginManager_UnitTest.t.sol";
import {IMarginAccount} from "../../../../contracts/Interfaces/IMarginAccount.sol";
import {IRiskManager} from "../../../../contracts/Interfaces/IRiskManager.sol";

// acv = account value
contract RepayVault_MarginManager_UnitTest is MarginManager_UnitTest {
    function test_repayVault_when_invalid_trader(
        uint256 borrowAmount
    ) public invalidMarginAccount {
        vm.assume(borrowAmount > 1 && borrowAmount < 10);
        vm.expectRevert("MM: Invalid margin account");
        vm.prank(david);
        contracts.marginManager.repayVault(borrowAmount * ONE_USDC);
    }

    function test_repayVault_zero_amount() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        uint256 borrowAmount = chronuxMargin;
        vm.prank(bob);
        contracts.marginManager.borrowFromVault(borrowAmount);
        vm.expectRevert("MM: repaying 0 amount not allowed");
        vm.prank(bob);
        contracts.marginManager.repayVault(0);
    }

    function test_repayVault_without_borrow() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(alice, usdc, chronuxMargin);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        uint256 borrowAmount = chronuxMargin;
        vm.prank(alice);
        contracts.marginManager.borrowFromVault(borrowAmount);
        vm.expectRevert(
            "MarginAccount: Decrease debt amount exceeds total debt"
        );
        vm.prank(bob);
        contracts.marginManager.repayVault(borrowAmount);
    }

    function test_repayVault_with_valid_input() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(alice, usdc, chronuxMargin);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        uint256 borrowAmount = chronuxMargin;
        vm.prank(bob);
        contracts.marginManager.borrowFromVault(borrowAmount);
        vm.expectCall(
            bobMarginAccount,
            abi.encodeCall(IMarginAccount.decreaseDebt, (borrowAmount, 0))
        );
        vm.expectCall(
            address(contracts.vault),
            abi.encodeCall(
                contracts.vault.repay,
                (bobMarginAccount, borrowAmount, 0)
            )
        );
        vm.prank(bob);
        contracts.marginManager.repayVault(borrowAmount);
    }
}
