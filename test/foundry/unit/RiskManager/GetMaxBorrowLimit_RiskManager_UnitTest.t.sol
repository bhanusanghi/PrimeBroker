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

contract GetMaxBorrowLimit_RiskManager_UnitTest is RiskManager_UnitTest {
    uint256 maxLeverageMultiplier = 4;
    uint256 maxBorrowMultiplier = 3;

    function test_Zero_BorrowLimit_When_InvalidMarginAccount()
        public
        invalidMarginAccount
    {
        vm.expectRevert();
        uint256 limit = contracts.riskManager.getMaxBorrowLimit(david);
    }

    function test_zero_borrow_limit_when_zero_collateral()
        public
        validMarginAccount
        zeroCollateral
    {
        uint256 bLimit = contracts.riskManager.getMaxBorrowLimit(
            bobMarginAccount
        );
        assertEq(bLimit, 0);
    }

    function test_borrow_limit_when_fresh_borrow()
        public
        validMarginAccount
        nonZeroCollateral
        freshBorrow
    {
        uint256 margin = 1000 * ONE_USDC;
        uint256 marginX18 = 1000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        uint256 bLimit = contracts.riskManager.getMaxBorrowLimit(
            bobMarginAccount
        );
        assertEq(bLimit, marginX18 * maxBorrowMultiplier);
    }

    function test_borrow_limit_when_previously_borrowed()
        public
        validMarginAccount
        nonZeroCollateral
        previouslyBorrowed
    {
        uint256 margin = 1000 * ONE_USDC;
        uint256 marginX18 = 1000 ether;
        uint256 maxBLimit = marginX18 * maxBorrowMultiplier;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        vm.startPrank(bob);
        uint256 bLimit = contracts.riskManager.getMaxBorrowLimit(
            bobMarginAccount
        );
        assertEq(bLimit, maxBLimit);
        contracts.marginManager.borrowFromVault(1000 * ONE_USDC);
        bLimit = contracts.riskManager.getMaxBorrowLimit(bobMarginAccount);
        assertEq(bLimit, maxBLimit);
        contracts.marginManager.borrowFromVault(1000 * ONE_USDC);
        bLimit = contracts.riskManager.getMaxBorrowLimit(bobMarginAccount);
        assertEq(bLimit, maxBLimit);
        contracts.marginManager.borrowFromVault(1000 * ONE_USDC);
        bLimit = contracts.riskManager.getMaxBorrowLimit(bobMarginAccount);
        assertEq(bLimit, maxBLimit);
        vm.stopPrank();
    }
}
