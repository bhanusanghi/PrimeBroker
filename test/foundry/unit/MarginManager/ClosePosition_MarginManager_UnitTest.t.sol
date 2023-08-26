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
import {IProtocolRiskManager} from "../../../../contracts/Interfaces/IProtocolRiskManager.sol";
import {LiquidationParams} from "../../utils/ChronuxUtils.sol";
import {IAccountBalance} from "../../../../contracts/Interfaces/Perpfi/IAccountBalance.sol";

// acv = account value
contract ClosePosition_MarginManager_UnitTest is MarginManager_UnitTest {
    function test_closePosition_when_invalid_trader()
        public
        invalidMarginAccount
    {
        address[] memory destinations = new address[](0);
        bytes[] memory data = new bytes[](0);
        vm.prank(david);
        vm.expectRevert("MM: Invalid margin account");
        contracts.marginManager.closePosition(snxUniKey, destinations, data);
    }

    function test_closePosition_when_liquidated_on_TPP() public {
        uint256 margin = 1000 * ONE_USDC;
        int256 notional = int256(2000 ether);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, margin);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            int256(margin),
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );
        vm.mockCall(
            perpAccountBalance,
            abi.encodeWithSelector(
                IAccountBalance.getTakerOpenNotional.selector
            ),
            abi.encode(0)
        );
        vm.mockCall(
            perpAccountBalance,
            abi.encodeWithSelector(
                IAccountBalance.getTotalOpenNotional.selector
            ),
            abi.encode(0)
        );
        //@note - Since we are still not sure on this wrt. throw the error, or just rely on tpp revert.
        // perpfiUtils.revertClosePosition(
        //     bob,
        //     perpAaveKey,
        //     "MM: Trader does not have active position in this market"
        // );
        // TODO - resolve the sync bug.
        // assertEq(
        //     IMarginAccount(bobMarginAccount).isActivePosition(perpAaveKey),
        //     false
        // );
    }

    function test_closePosition_when_invalid_calldata() public {
        uint256 margin = 1000 * ONE_USDC;
        int256 notional = int256(2000 ether);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, margin);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            int256(margin),
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );
        vm.mockCallRevert(
            address(contracts.perpfiRiskManager),
            abi.encodeWithSelector(
                IProtocolRiskManager.decodeClosePositionCalldata.selector
            ),
            bytes("invalid close call")
        );
        perpfiUtils.revertClosePosition(
            bob,
            perpAaveKey,
            bytes("invalid close call")
        );
    }

    function test_closePosition_when_final_size_not_zero() public {
        uint256 margin = 1000 * ONE_USDC;
        int256 notional = int256(2000 ether);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, margin);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            int256(margin),
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );
        vm.mockCall(
            perpAccountBalance,
            abi.encodeWithSelector(
                IAccountBalance.getTakerOpenNotional.selector
            ),
            abi.encode(notional)
        );
        perpfiUtils.revertClosePosition(
            bob,
            perpAaveKey,
            "MM: Invalid close position call"
        );
    }

    function test_closePosition_when_final_health_bad() public {
        uint256 margin = 1000 * ONE_USDC;
        int256 notional = int256(2000 ether);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, margin);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            int256(margin),
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );
        vm.mockCall(
            address(contracts.riskManager),
            abi.encodeWithSelector(IRiskManager.isAccountHealthy.selector),
            abi.encode(false)
        );
        perpfiUtils.revertClosePosition(
            bob,
            perpAaveKey,
            "MM: Unhealthy account"
        );
    }

    function test_closePosition_when_final_health_good() public {
        uint256 margin = 1000 * ONE_USDC;
        int256 notional = int256(2000 ether);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, margin);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            int256(margin),
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );
        perpfiUtils.closeAndVerifyPosition(bob, perpAaveKey);
    }
}
