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
import {SettlementTokenMath} from "../../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MarginAccount} from "../../../contracts/MarginAccount/MarginAccount.sol";
import {Position} from "../../../contracts/Interfaces/IMarginAccount.sol";
import {IUniswapV3Pool} from "../../../contracts/Interfaces/IUniswapV3Pool.sol";
import {IEvents} from "../IEvents.sol";
import "forge-std/console2.sol";

contract ChronuxUtils is Test, IEvents {
    address usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    Contracts contracts;

    constructor(Contracts _contracts) {
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
        emit CollateralAdded(marginAccount, usdc, amount, amount);
        contracts.collateralManager.addCollateral(token, amount);
        vm.stopPrank();
    }

    function verifyRemainingTransferableMargin(
        address trader,
        uint256 amount
    ) external {
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        uint256 remainingMargin = contracts
            .riskManager
            .getRemainingMarginTransfer(marginAccount);
        assertEq(
            remainingMargin,
            amount,
            "remaining transferrable margin is not equal to amount"
        );
    }

    function verifyRemainingPositionNotional(
        address trader,
        uint256 deltaNotional
    ) external {
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        uint256 remainingNotional = contracts
            .riskManager
            .getRemainingPositionOpenNotional(marginAccount);
        assertEq(
            remainingNotional,
            deltaNotional,
            "remaining positionNotional is not equal to amount"
        );
    }
}
