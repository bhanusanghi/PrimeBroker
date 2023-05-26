pragma solidity ^0.8.10;
import {Test} from "forge-std/Test.sol";
import {IMarketRegistry} from "../../../contracts/Interfaces/Perpfi/IMarketRegistry.sol";
import {SettlementTokenMath} from "../../../contracts/Libraries/SettlementTokenMath.sol";
import {IMarginAccount} from "../../../contracts/Interfaces/IMarginAccount.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MarginAccount} from "../../../contracts/MarginAccount/MarginAccount.sol";
import {Position} from "../../../contracts/Interfaces/IMarginAccount.sol";
import {IUniswapV3Pool} from "../../../contracts/Interfaces/IUniswapV3Pool.sol";
import {IEvents} from "../IEvents.sol";
import {Constants} from "./Constants.sol";
import "forge-std/console2.sol";

contract ChronuxUtils is Test, Constants, IEvents {
    Contracts contracts;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;

    constructor(Contracts memory _contracts) {
        contracts = _contracts;
    }

    function depositAndVerifyMargin(
        address trader,
        address token,
        uint256 amount
    ) external {
        vm.startPrank(trader);
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        IERC20(token).approve(marginAccount, amount);
        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(contracts.collateralManager)
        );
        uint256 amountInVaultAssetDecimals = amount.convertTokenDecimals(
            ERC20(token).decimals(),
            ERC20(contracts.vault.asset()).decimals()
        );
        emit CollateralAdded(
            marginAccount,
            token,
            amount,
            amountInVaultAssetDecimals
        );
        contracts.collateralManager.addCollateral(token, amount);
        vm.stopPrank();
    }

    function verifyRemainingTransferableMargin(
        address trader,
        int256 amount
    ) external {
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        uint256 remainingMargin = contracts
            .riskManager
            .getRemainingMarginTransfer(marginAccount);
        assertEq(
            int256(remainingMargin),
            amount,
            "remaining transferrable margin is not equal to amount"
        );
    }

    function verifyRemainingPositionNotional(
        address trader,
        int256 expectedRemainingNotional
    ) external {
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        uint256 remainingNotional = contracts
            .riskManager
            .getRemainingPositionOpenNotional(marginAccount);

        assertApproxEqAbs(
            int256(remainingNotional),
            expectedRemainingNotional,
            DUST_THRESHOLD,
            "remaining positionNotional is not equal to amount"
        );
    }
}
