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
import {IRiskManager} from "../../../../contracts/Interfaces/IRiskManager.sol";

// acv = account value
contract OpenPosition_MarginManager_UnitTest is MarginManager_UnitTest {
    function test_openPosition_when_trader_isLiquidatable(
        int256 marginMultiplier
    ) public isLiquidatable {
        vm.assume(marginMultiplier > -10 && marginMultiplier < 10);
        vm.mockCall(
            address(contracts.riskManager),
            abi.encodeWithSelector(IRiskManager.isAccountLiquidatable.selector),
            abi.encode(true, true, 0)
        );
        snxUtils.updateAndVerifyMargin(
            bob,
            snxUniKey,
            marginMultiplier * int256(100 * ONE_USDC),
            true,
            "MM: Account is liquidatable"
        );
        snxUtils.addAndVerifyPosition(
            bob,
            snxUniKey,
            marginMultiplier * 1 ether,
            true,
            "MM: Account is liquidatable"
        );
    }

    function test_openPosition_when_isExistingPosition()
        public
        isExistingPosition
    {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            int256(100 * ONE_USDC),
            false,
            ""
        );
        perpfiUtils.addAndVerifyPositionSize(
            bob,
            perpAaveKey,
            1 ether,
            false,
            ""
        );
        perpfiUtils.addAndVerifyPositionSize(
            bob,
            perpAaveKey,
            1 ether,
            true,
            "Existing position"
        );
    }

    function test_openPosition_when_invalidTrade() public invalidTrade {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        vm.mockCallRevert(
            address(contracts.riskManager),
            abi.encodeWithSelector(IRiskManager.verifyTrade.selector),
            abi.encode("Invalid Trade")
        );
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            int256(100 * ONE_USDC),
            true,
            abi.encode("Invalid Trade")
        );
        perpfiUtils.addAndVerifyPositionSize(
            bob,
            perpAaveKey,
            1 ether,
            true,
            abi.encode("Invalid Trade")
        );
    }
}
