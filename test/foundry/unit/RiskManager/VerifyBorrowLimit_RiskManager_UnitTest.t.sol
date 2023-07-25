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

contract VerifyBorrowLimit_RiskManager_UnitTest is RiskManager_UnitTest {
    function test_verifyBorrowLimit_reverts_on_crossing_borrow_limit()
        public
        validMarginAccount
    {
        uint256 borrowAmount = 1 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 100 * ONE_USDC);
        vm.prank(bob);
        contracts.marginManager.borrowFromVault(300 * ONE_USDC);
        vm.expectRevert("Borrow limit exceeded");
        contracts.riskManager.verifyBorrowLimit(bobMarginAccount, borrowAmount);
    }

    function test_verifyBorrowLimit_works()
        public
        validMarginAccount
        nonZeroCollateral
    {
        uint256 borrowAmount = 1 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 100 * ONE_USDC);
        vm.prank(bob);
        contracts.marginManager.borrowFromVault(200 * ONE_USDC);
        contracts.riskManager.verifyBorrowLimit(bobMarginAccount, borrowAmount);
    }
}
