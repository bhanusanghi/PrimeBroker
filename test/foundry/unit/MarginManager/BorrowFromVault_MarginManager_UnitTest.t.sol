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
contract BorrowFromVault_MarginManager_UnitTest is MarginManager_UnitTest {
    function test_borrowFromVault_when_invalid_trader(
        uint256 borrowAmount
    ) public invalidMarginAccount {
        vm.assume(borrowAmount > 1 && borrowAmount < 10);
        vm.expectRevert("MM: Invalid margin account");
        vm.prank(david);
        contracts.marginManager.borrowFromVault(borrowAmount * ONE_USDC);
    }

    function test_borrowFromVault_zero_amount() public {
        uint256 borrowAmount = 0;
        vm.expectRevert("MM: Borrow amount should be greater than zero");
        vm.prank(bob);
        contracts.marginManager.borrowFromVault(borrowAmount);
    }

    function test_borrowFromVault_over_borrow_limit() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        uint256 borrowAmount = chronuxMargin * 3;
        vm.startPrank(bob);
        contracts.marginManager.borrowFromVault(borrowAmount);
        vm.expectRevert("Borrow limit exceeded");
        contracts.marginManager.borrowFromVault(ONE_USDC);
        vm.stopPrank();
    }

    function test_borrowFromVault_within_borrow_limit() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        uint256 borrowAmount = chronuxMargin * 2;
        vm.startPrank(bob);
        vm.expectCall(
            bobMarginAccount,
            abi.encodeCall(IMarginAccount.increaseDebt, (borrowAmount))
        );
        vm.expectCall(
            address(contracts.vault),
            abi.encodeCall(
                contracts.vault.borrow,
                (bobMarginAccount, borrowAmount)
            )
        );
        contracts.marginManager.borrowFromVault(borrowAmount);
        vm.stopPrank();
    }

    function test_borrowFromVault_when_unhealthy() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        uint256 borrowAmount = chronuxMargin * 3;
        vm.mockCall(
            address(contracts.riskManager),
            abi.encodeWithSelector(IRiskManager.isAccountHealthy.selector),
            abi.encode(false)
        );
        vm.startPrank(bob);
        vm.expectRevert("MM: Unhealthy account");
        contracts.marginManager.borrowFromVault(borrowAmount);
        vm.stopPrank();
    }
}
