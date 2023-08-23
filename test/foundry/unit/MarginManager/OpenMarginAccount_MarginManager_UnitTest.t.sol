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
import {IMarginAccount, Position} from "../../../../contracts/Interfaces/IMarginAccount.sol";
import {IProtocolRiskManager} from "../../../../contracts/Interfaces/IProtocolRiskManager.sol";

// acv = account value
contract OpenMarginAccount_MarginManager_UnitTest is MarginManager_UnitTest {
    function test_reverts_when_duplicate_trader() public {
        vm.startPrank(david);
        contracts.marginManager.openMarginAccount();
        vm.expectRevert("MM: Margin account already exists");
        contracts.marginManager.openMarginAccount();
        vm.stopPrank();
    }

    function test_open_margin_account() public {
        vm.startPrank(david);
        vm.expectEmit(
            true,
            false,
            false,
            false,
            address(contracts.marginManager)
        );
        emit MarginAccountOpened(david, address(0));
        address marginAccount = contracts.marginManager.openMarginAccount();
        assertEq(
            IERC20(contracts.vault.asset()).allowance(
                marginAccount,
                address(contracts.vault)
            ),
            type(uint256).max
        );
        assertEq(
            contracts.marginManager.getMarginAccount(david),
            marginAccount
        );
        vm.stopPrank();
    }

    function test_open_margin_account_when_unused_accounts_exist() public {
        chronuxUtils.depositAndVerifyMargin(bob, susd, 100 ether);
        chronuxUtils.withdrawAndVerifyMargin(bob, susd, 100 ether);
        vm.prank(bob);
        contracts.marginManager.closeMarginAccount();

        vm.startPrank(david);
        vm.expectEmit(true, true, true, true, address(contracts.marginManager));
        emit MarginAccountOpened(david, bobMarginAccount);
        address marginAccount = contracts.marginManager.openMarginAccount();
        assertEq(
            IERC20(contracts.vault.asset()).allowance(
                marginAccount,
                address(contracts.vault)
            ),
            type(uint256).max
        );
        vm.stopPrank();
    }
}
