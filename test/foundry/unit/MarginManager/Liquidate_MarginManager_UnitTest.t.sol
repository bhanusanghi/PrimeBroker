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
import {LiquidationParams} from "../../utils/ChronuxUtils.sol";
import {IFuturesMarket} from "../../../../contracts/Interfaces/SNX/IFuturesMarket.sol";

// acv = account value
contract Liquidate_MarginManager_UnitTest is MarginManager_UnitTest {
    function test_liquidate_when_invalid_trader() public invalidMarginAccount {
        LiquidationParams memory params = chronuxUtils.getLiquidationData(bob);
        vm.prank(alice);
        vm.expectRevert("MM: Invalid margin account");
        contracts.marginManager.liquidate(
            david,
            params.activeMarkets,
            params.destinations,
            params.data
        );
    }

    function test_liquidate_when_invalid_liquidation() public {
        LiquidationParams memory params = chronuxUtils.getLiquidationData(bob);
        vm.prank(alice);
        vm.mockCallRevert(
            address(contracts.riskManager),
            abi.encodeWithSelector(IRiskManager.verifyLiquidation.selector),
            bytes("is not a valid liquidation")
        );
        vm.expectRevert("is not a valid liquidation");
        contracts.marginManager.liquidate(
            bob,
            params.activeMarkets,
            params.destinations,
            params.data
        );
    }

    function test_liquidate_when_final_margin_in_TPP_not_zero() public {
        int256 margin = int256(1000 * ONE_USDC);
        int256 notional = int256(100 * ONE_USDC);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * ONE_USDC);
        perpfiUtils.updateAndVerifyMargin(bob, perpAaveKey, margin, false, "");
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );
        vm.mockCall(
            address(contracts.riskManager),
            abi.encodeWithSelector(IRiskManager.verifyLiquidation.selector),
            abi.encode(true, alice, 0)
        );
        vm.mockCall(
            address(contracts.riskManager),
            abi.encodeWithSelector(IRiskManager.isAccountLiquidatable.selector),
            abi.encode(true, true, 0)
        );
        LiquidationParams memory params;
        params.activeMarkets = new bytes32[](1);
        params.destinations = new address[](1);
        params.data = new bytes[](1);
        (address destination, bytes memory data) = chronuxUtils
            .getPerpfiClosePositionData(perpAaveKey);
        params.activeMarkets[0] = perpAaveKey;
        params.destinations[0] = destination;
        params.data[0] = data;
        vm.prank(alice);
        vm.expectRevert("MM: Margin not transferred back to Chronux");
        contracts.marginManager.liquidate(
            bob,
            params.activeMarkets,
            params.destinations,
            params.data
        );
    }

    function test_liquidate_when_final_margin_in_another_TPP_not_zero() public {
        int256 margin = int256(1000 * ONE_USDC);
        int256 snxMargin = int256(1000 ether);
        int256 notional = int256(100 ether);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * ONE_USDC);
        perpfiUtils.updateAndVerifyMargin(bob, perpAaveKey, margin, false, "");
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );
        LiquidationParams memory params = chronuxUtils.getLiquidationData(bob);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        snxUtils.updateAndVerifyPositionSize(bob, snxUniKey, 1 ether, false, "");
        vm.mockCall(
            address(contracts.riskManager),
            abi.encodeWithSelector(IRiskManager.verifyLiquidation.selector),
            abi.encode(true, alice, 0)
        );
        vm.mockCall(
            address(contracts.riskManager),
            abi.encodeWithSelector(IRiskManager.isAccountLiquidatable.selector),
            abi.encode(true, true, 0)
        );

        vm.prank(alice);
        vm.expectRevert("MM: Margin not transferred back to Chronux");
        contracts.marginManager.liquidate(
            bob,
            params.activeMarkets,
            params.destinations,
            params.data
        );
    }

    function test_liquidate_when_trader_has_vault_liability_no_bad_debt()
        public
    {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        int256 snxMargin = int256(2000 ether);
        int256 notional = int256(3600 ether);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 positionSize = (notional * 1 ether) / int256(assetPrice);
        snxUtils.updateAndVerifyPositionSize(bob, snxUniKey, positionSize, false, "");
        utils.mineBlocks(100, 1 days); // accrues funding rate and interest
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(snxUniKey);
        utils.simulateUnrealisedPnLSnx(
            circuitBreaker,
            bobMarginAccount,
            snxUni_marketKey,
            openPosition.openNotional,
            openPosition.size,
            -280 ether
        );
        LiquidationParams memory params = chronuxUtils.getLiquidationData(bob);
        uint256 interestX18 = 10 ether;
        // assertEq(liqPenalty, ((1000 ether - 280 ether - interest) * 2) / 100);
        vm.mockCall(
            bobMarginAccount,
            abi.encodeWithSelector(
                IMarginAccount.getInterestAccruedX18.selector
            ),
            abi.encode(interestX18)
        );
        uint256 interest = interestX18 / 1e12;
        (bool isLiquit, , uint256 liqPenalty) = contracts
            .riskManager
            .isAccountLiquidatable(bobMarginAccount);
        assertEq(isLiquit, true);

        liqPenalty = liqPenalty / 1e12;
        (int256 accruedFunding, ) = IFuturesMarket(market).accruedFunding(
            bobMarginAccount
        );
        uint256 initialBalanceAlice = IERC20(usdc).balanceOf(alice);
        uint256 initialBalanceVault = IERC20(usdc).balanceOf(
            address(contracts.vault)
        );
        uint256 accValue = contracts.riskManager.getAccountValue(
            bobMarginAccount
        );
        (uint256 orderFee, ) = IFuturesMarket(market).orderFee(positionSize);
        vm.prank(alice);
        contracts.marginManager.liquidate(
            bob,
            params.activeMarkets,
            params.destinations,
            params.data
        );
        assertEq(
            IERC20(susd).balanceOf(bobMarginAccount),
            0,
            "balance of susd should be 0"
        );
        assertApproxEqAbs(
            IERC20(usdc).balanceOf(alice),
            initialBalanceAlice + liqPenalty,
            1 * ONE_USDC,
            "liquidator was not paid"
        );
        assertApproxEqAbs(
            int256(IERC20(usdc).balanceOf(bobMarginAccount)),
            int256((accValue / 1e12)) -
                int256(liqPenalty) -
                (accruedFunding / 1e12) -
                int256(orderFee / 1e12),
            3 * ONE_USDC,
            "bobMarginAccount balance after liquidation is wrong"
        );
        // // withdrawable margin should be equal to current account balance
        // // assertApproxEqAbs()
        assertApproxEqAbs(
            IERC20(usdc).balanceOf(address(contracts.vault)),
            initialBalanceVault + 1100 * ONE_USDC + interest,
            5 * ONE_USDC,
            "vault balance after liquidation is wrong"
        );

        assertEq(
            contracts.collateralManager.getFreeCollateralValue(
                bobMarginAccount
            ) / 1e12,
            IERC20(usdc).balanceOf(bobMarginAccount)
        );
    }
}
