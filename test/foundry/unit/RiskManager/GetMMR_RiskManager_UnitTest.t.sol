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

contract Get_MMR_RiskManager_UnitTest is RiskManager_UnitTest {
    function test_reverts_when_invalid_account() public invalidMarginAccount {
        uint256 mmr = contracts.riskManager.getMaintenanceMarginRequirement(
            david
        );
        assertEq(mmr, 0);
    }

    function test_mmr_is_zero_when_no_collateral()
        public
        validMarginAccount
        zeroCollateral
    {
        uint256 mmr = contracts.riskManager.getMaintenanceMarginRequirement(
            bobMarginAccount
        );
        assertEq(mmr, 0);
    }

    function test_mmr_is_zero_when_no_open_positions()
        public
        validMarginAccount
        nonZeroCollateral
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        uint256 mmr = contracts.riskManager.getMaintenanceMarginRequirement(
            bobMarginAccount
        );
        assertEq(mmr, 0);
    }

    function test_mmr_value_when_open_positions()
        public
        validMarginAccount
        nonZeroCollateral
        noOpenPosition
    {
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
        int256 pnl = -100 ether;
        vm.mockCall(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.getUnrealizedPnL.selector
            ),
            abi.encode(pnl)
        );
        uint256 mmr = contracts.riskManager.getMaintenanceMarginRequirement(
            bobMarginAccount
        );
        assertEq(
            mmr,
            780 ether // 4000/5
        );
    }
}
