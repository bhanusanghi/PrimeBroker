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

    function test_zero_bp_when_0_collateral() public {
        uint256 accountValue = contracts.riskManager.getAccountValue(bob);
        assertEq(accountValue, 0);
    }

    function test_acv_with_interest() public {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        uint256 interestX18 = 100 ether;
        vm.mockCall(
            bobMarginAccount,
            abi.encodeWithSelector(
                IMarginAccount.getInterestAccruedX18.selector
            ),
            abi.encode(interestX18)
        );
        uint256 accountValue = contracts.riskManager.getAccountValue(
            bobMarginAccount
        );
        assertEq(accountValue, (1000 - 100) * 1 ether);
    }

    function test_acv_with_positive_unrealised_pnl() public {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        int256 pnl = 100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        uint256 accountValue = contracts.riskManager.getAccountValue(
            bobMarginAccount
        );
        assertEq(accountValue, (1000 + 100) * 1 ether);
    }

    function test_acv_with_negative_unrealised_pnl() public {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        int256 pnl = 100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(-pnl)
        );
        uint256 accountValue = contracts.riskManager.getAccountValue(
            bobMarginAccount
        );
        assertEq(accountValue, (1000 - 100) * 1 ether);
    }

    function test_acv_with_interest_and_negative_unrealised_pnl() public {
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
        uint256 accountValue = contracts.riskManager.getAccountValue(
            bobMarginAccount
        );
        assertEq(accountValue, (1000 - 100 - 100) * 1 ether);
    }

    function test_acv_with_interest_and_positive_unrealised_pnl() public {
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
        uint256 accountValue = contracts.riskManager.getAccountValue(
            bobMarginAccount
        );
        assertEq(accountValue, (1000 - 100 + 220) * 1 ether);
    }

    function test_negative_tcv() public {
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
        uint256 accountValue = contracts.riskManager.getAccountValue(
            bobMarginAccount
        );
        assertEq(accountValue, 0);
    }

    function test_negative_tcv_with_negative_pnl() public {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        int256 pnl = -2000 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        uint256 interestX18 = 0 ether;
        vm.mockCall(
            bobMarginAccount,
            abi.encodeWithSelector(
                IMarginAccount.getInterestAccruedX18.selector
            ),
            abi.encode(interestX18)
        );
        uint256 accountValue = contracts.riskManager.getAccountValue(
            bobMarginAccount
        );
        assertEq(accountValue, 0);
    }
}
