pragma solidity ^0.8.10;
import "forge-std/console2.sol";
import {MarginManager_UnitTest} from "./MarginManager_UnitTest.t.sol";
import {IMarginAccount, Position} from "../../../../contracts/Interfaces/IMarginAccount.sol";

// acv = account value
contract CloseMarginAccount_MarginManager_UnitTest is MarginManager_UnitTest {
    function test_closeMarginAccount_invalidTrader()
        public
        invalidMarginAccount
    {
        vm.prank(david);
        vm.expectRevert("MM: Invalid margin account");
        contracts.marginManager.closeMarginAccount();
    }

    function test_closeAccount_withCollateral() public {
        chronuxUtils.depositAndVerifyMargin(bob, susd, 100 ether);
        vm.prank(bob);
        vm.expectRevert("MM: Cannot close account with collateral");
        contracts.marginManager.closeMarginAccount();
    }

    function test_valid_CloseAcccount() public invalidMarginAccount {
        chronuxUtils.depositAndVerifyMargin(bob, susd, 100 ether);
        chronuxUtils.withdrawAndVerifyMargin(bob, susd, 100 ether);
        vm.prank(bob);
        vm.expectEmit(true, true, true, true, address(contracts.marginManager));
        emit MarginAccountClosed(bob, bobMarginAccount);
        contracts.marginManager.closeMarginAccount();
        address[] memory unusedMarginAccounts = contracts
            .marginAccountFactory
            .getUnusedMarginAccounts();
        assertEq(unusedMarginAccounts.length, 1);
        assertEq(unusedMarginAccounts[0], bobMarginAccount);
    }
}
