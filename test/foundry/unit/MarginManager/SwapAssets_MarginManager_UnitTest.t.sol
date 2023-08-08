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
import {IMarginAccount} from "../../../../contracts/Interfaces/IMarginAccount.sol";
import {IRiskManager} from "../../../../contracts/Interfaces/IRiskManager.sol";

// acv = account value
contract SwapAssets_MarginManager_UnitTest is MarginManager_UnitTest {
    function test_swapAssets_when_invalid_trader() public invalidMarginAccount {
        vm.expectRevert("MM: Invalid margin account");
        vm.prank(david);
        contracts.marginManager.swapAsset(
            usdc,
            susd,
            100 * ONE_USDC,
            99 * ONE_USDC
        );
    }

    function test_swapAssets_when_Unhealthy() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        vm.mockCall(
            address(contracts.riskManager),
            abi.encodeWithSelector(IRiskManager.isAccountHealthy.selector),
            abi.encode(false)
        );
        vm.expectRevert("MM: Unhealthy account");
        vm.prank(bob);
        contracts.marginManager.swapAsset(
            usdc,
            susd,
            100 * ONE_USDC,
            99 * ONE_USDC
        );
    }

    function test_swapAssets_when_invalid_tokenOut() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        vm.expectRevert("MM: Invalid tokenOut");
        vm.prank(bob);
        contracts.marginManager.swapAsset(
            usdc,
            usdt,
            100 * ONE_USDC,
            99 * ONE_USDC
        );
    }

    function test_swapAssets_when_invalid_tokenIn() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        vm.expectRevert("MM: Invalid tokenIn");
        vm.prank(bob);
        contracts.marginManager.swapAsset(
            usdt,
            usdc,
            100 * ONE_USDC,
            99 * ONE_USDC
        );
    }

    function test_swapAssets_when_tokenOut_equals_tokenIn() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        vm.expectRevert("MM: Same token");
        vm.prank(bob);
        contracts.marginManager.swapAsset(
            usdc,
            usdc,
            100 * ONE_USDC,
            99 * ONE_USDC
        );
    }

    function test_swapAssets_when_tokenIn_equals_zero() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        vm.expectRevert();
        vm.prank(bob);
        contracts.marginManager.swapAsset(usdc, susd, 0, 99 * ONE_USDC);
    }

    function test_swapAssets_when_no_path_found() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        vm.prank(deployerAdmin);
        contracts.contractRegistry.updateCurvePool(usdc, susd, address(0));
        vm.expectRevert("Invalid Curve pool");
        vm.prank(bob);
        contracts.marginManager.swapAsset(
            usdc,
            susd,
            100 * ONE_USDC,
            99 * ONE_USDC
        );
    }

    function test_swapAssets_when_excess_slippage() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        vm.expectRevert();
        vm.prank(bob);
        uint256 amountOut = contracts.marginManager.swapAsset(
            usdc,
            susd,
            100 * ONE_USDC,
            100 ether
        );
    }

    function test_swapAssets_when_final_health_becomes_low() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        vm.mockCall(
            address(contracts.riskManager),
            abi.encodeWithSelector(IRiskManager.isAccountHealthy.selector),
            abi.encode(false)
        );
        vm.expectRevert("MM: Unhealthy account");
        vm.prank(bob);
        uint256 amountOut = contracts.marginManager.swapAsset(
            usdc,
            susd,
            100 * ONE_USDC,
            98 ether
        );
    }

    function test_swapAssets_updates_account_balances() public {
        uint256 chronuxMargin = 100 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        vm.prank(bob);
        uint256 amountOut = contracts.marginManager.swapAsset(
            usdc,
            susd,
            100 * ONE_USDC,
            98 ether
        );
        assertEq(
            IERC20(usdc).balanceOf(bobMarginAccount),
            0,
            "tokenIn balance after swap does not match"
        );
        assertEq(
            IERC20(susd).balanceOf(bobMarginAccount),
            amountOut,
            "tokenOut balance after swap does not match"
        );
    }
    // invalid index
    // function test_swapAssets_when_invalid_index() public {
    //     uint256 chronuxMargin = 100 * ONE_USDC;
    //     chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
    //     vm.expectRevert("MM: Same token");
    //     vm.prank(bob);
    //     contracts.contractRegistry.updateCurveTokenIndex(
    //         usdc,
    //         susd,
    //         address(0)
    //     );
    //     contracts.marginManager.swapAsset(
    //         usdc,
    //         usdc,
    //         100 * ONE_USDC,
    //         99 * ONE_USDC
    //     );
    // }
}
