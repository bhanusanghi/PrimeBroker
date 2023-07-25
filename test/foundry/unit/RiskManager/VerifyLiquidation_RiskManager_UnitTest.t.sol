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

contract VerifyLiquidation_RiskManager_UnitTest is RiskManager_UnitTest {

    bytes32[] memory activeMarkets = new bytes32[](resultLength);
        params.destinations = new address[](resultLength);
        params.data = new bytes[](resultLength);
    function test_reverts_when_invalid_caller() public invalidMarginAccount {
        vm.expectRevert("RiskManager: Only margin manager");
        contracts.riskManager.verifyLiquidation(david);
    }

    function test_reverts_when_invalid_account() public invalidMarginAccount {
        vm.prank(address(contracts.marginManager));
        vm.expectRevert();
        contracts.riskManager.verifyLiquidation(david);
    }

    function test_reverts_when_no_open_positions() public validMarginAccount {
        vm.prank(address(contracts.marginManager));
        vm.expectRevert("PRM: Account not liquidatable");
        contracts.riskManager.verifyLiquidation(bobMarginAccount);
    }

    function test_revert_when_enough_margin()
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
        int256 pnl = -100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        vm.prank(address(contracts.marginManager));
        vm.expectRevert("PRM: Account not liquidatable");
        contracts.riskManager.verifyLiquidation(bobMarginAccount);
    }

    function test_result_when_low_margin()
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
        int256 pnl = -600 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        vm.prank(address(contracts.marginManager));
        vm.expectRevert("PRM: Account not liquidatable");
        VerifyLiquidationResult memory result = contracts
            .riskManager
            .verifyLiquidation(bobMarginAccount);
        assertEq(result.liquidationPenalty, 20 ether);
        assertEq(result.isFullyLiquidatable, true);
    }
}
