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
    function test_reverts_when_invalid_caller() public invalidMarginAccount {
        bytes32[] memory activeMarkets = new bytes32[](1);
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        vm.expectRevert("RiskManager: Only margin manager");
        contracts.riskManager.verifyLiquidation(
            IMarginAccount(bobMarginAccount),
            activeMarkets,
            destinations,
            data
        );
    }

    function test_reverts_when_invalid_account() public invalidMarginAccount {
        bytes32[] memory activeMarkets = new bytes32[](1);
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        vm.prank(address(contracts.marginManager));
        vm.expectRevert();
        contracts.riskManager.verifyLiquidation(
            IMarginAccount(david),
            activeMarkets,
            destinations,
            data
        );
    }

    function test_reverts_when_no_open_positions() public validMarginAccount {
        bytes32[] memory activeMarkets = new bytes32[](1);
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        vm.prank(address(contracts.marginManager));
        vm.expectRevert("PRM: Account not liquidatable");
        contracts.riskManager.verifyLiquidation(
            IMarginAccount(bobMarginAccount),
            activeMarkets,
            destinations,
            data
        );
    }

    function test_revert_when_enough_margin()
        public
        validMarginAccount
        negativePnL
    {
        bytes32[] memory activeMarkets = new bytes32[](1);
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
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
        contracts.riskManager.verifyLiquidation(
            IMarginAccount(bobMarginAccount),
            activeMarkets,
            destinations,
            data
        );
    }

    function test_result_when_low_margin()
        public
        validMarginAccount
        negativePnL
    {
        bytes32[] memory activeMarkets = new bytes32[](1);
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        activeMarkets[0] = perpAaveKey;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            1000 * 1e6,
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            3900 ether,
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
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.decodeAndVerifyLiquidationCalldata.selector
            ),
            abi.encode("")
        );
        vm.prank(address(contracts.marginManager));
        VerifyLiquidationResult memory result = contracts
            .riskManager
            .verifyLiquidation(
                IMarginAccount(bobMarginAccount),
                activeMarkets,
                destinations,
                data
            );
        assertEq(
            result.liquidationPenaltyX18,
            78 ether, // 2% of notional
            "invalid liquidation penalty"
        );
        assertEq(result.isFullyLiquidatable, true);
    }
}
