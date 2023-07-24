pragma solidity ^0.8.10;

import "forge-std/console2.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SettlementTokenMath} from "../../../../contracts/Libraries/SettlementTokenMath.sol";
import {BaseSetup} from "../../BaseSetup.sol";
import {RiskManager_UnitTest} from "./RiskManager_UnitTest.sol";
import {IMarginAccount, Position} from "../../../../contracts/Interfaces/IMarginAccount.sol";
import {IProtocolRiskManager} from "../../../../contracts/Interfaces/IProtocolRiskManager.sol";

contract GetCurrentDollarMarginInMarkets_RiskManager_UnitTest is
    RiskManager_UnitTest
{
    function test_Zero_MIM_When_InvalidMarginAccount()
        public
        invalidMarginAccount
    {
        int256 mim = contracts.riskManager.getCurrentDollarMarginInMarkets(
            david
        );
        assertEq(mim, 0);
    }

    function test_zero_mim() public validMarginAccount {
        int256 mim = contracts.riskManager.getCurrentDollarMarginInMarkets(
            bobMarginAccount
        );
        assertEq(mim, 0);
    }

    function test_mim_single_tpp() public validMarginAccount {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        snxUtils.updateAndVerifyMargin(
            bob,
            snxUniKey,
            int256(1000 ether),
            false,
            ""
        );
        int256 mim = contracts.riskManager.getCurrentDollarMarginInMarkets(
            bobMarginAccount
        );
        assertEq(mim, 1000 ether);
    }

    function test_mim_single_tpp_multiple_markets()
        public
        validMarginAccount
        hasCollateralOnTPPs
        multipleMarkets
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        snxUtils.updateAndVerifyMargin(
            bob,
            snxUniKey,
            int256(1000 ether),
            false,
            ""
        );
        snxUtils.updateAndVerifyMargin(
            bob,
            snxEthKey,
            int256(1000 ether),
            false,
            ""
        );
        int256 mim = contracts.riskManager.getCurrentDollarMarginInMarkets(
            bobMarginAccount
        );
        assertEq(mim, 2000 ether);
    }

    function test_mim_multiple_tpps()
        public
        validMarginAccount
        hasCollateralOnTPPs
        multipleTPPs
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * 1e6);
        snxUtils.updateAndVerifyMargin(
            bob,
            snxUniKey,
            int256(1000 ether),
            false,
            ""
        );
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            int256(1000 * ONE_USDC),
            false,
            ""
        );
        int256 mim = contracts.riskManager.getCurrentDollarMarginInMarkets(
            bobMarginAccount
        );
        assertEq(mim, 2000 ether);
    }
}
