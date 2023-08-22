// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import {FixedPoint96} from "../../../contracts/Libraries/FixedPoint96.sol";
import {FullMath} from "../../../contracts/Libraries/FullMath.sol";
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
import {IVault} from "../../../contracts/Interfaces/Perpfi/IVault.sol";
import {IExchange} from "../../../contracts/Interfaces/Perpfi/IExchange.sol";
import {IAccountBalance} from "../../../contracts/Interfaces/Perpfi/IAccountBalance.sol";
import {Constants} from "./Constants.sol";
import {IEvents} from "../IEvents.sol";
import "forge-std/console2.sol";

// This is useless force push comment, please remove after use

contract PerpfiUtils is Test, Constants, IEvents {
    using SettlementTokenMath for uint256;
    using Math for uint256;
    using Math for int256;
    using SignedMath for int256;
    using SettlementTokenMath for int256;

    address perpVault = 0xAD7b4C162707E0B2b5f6fdDbD3f8538A5fbA0d60;
    Contracts contracts;
    address usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address perpAccountBalance = 0xA7f3FC32043757039d5e13d790EE43edBcBa8b7c;

    constructor(Contracts memory _contracts) {
        contracts = _contracts;
    }

    function formatSqrtPriceX96ToPriceX96(
        uint160 sqrtPriceX96
    ) internal pure returns (uint256) {
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    function formatX10_18ToX96(
        uint256 valueX10_18
    ) internal pure returns (uint256) {
        return FullMath.mulDiv(valueX10_18, FixedPoint96.Q96, 1 ether);
    }

    function formatX96ToX10_18(
        uint256 valueX96
    ) internal pure returns (uint256) {
        return FullMath.mulDiv(valueX96, 1 ether, FixedPoint96.Q96);
    }

    // @notice Returns the price of th UniV3Pool.
    function getMarkPrice(
        address exchange,
        address perpMarketRegistry,
        address _baseToken
    ) public view returns (uint256 token0Price) {
        uint160 val = IExchange(exchange).getSqrtMarkTwapX96(_baseToken, 0);
        return
            formatX96ToX10_18(
                formatSqrtPriceX96ToPriceX96(
                    IExchange(exchange).getSqrtMarkTwapX96(_baseToken, 0)
                )
            );
    }

    function fetchMargin(
        address marginAccount,
        bytes32 marketKey
    ) public returns (int256 margin) {
        margin = int256(IVault(perpVault).getBalance(marginAccount));
    }

    function getAccountValue(
        address marginAccount
    ) public returns (int256 accountValue) {
        accountValue = int256(IVault(perpVault).getAccountValue(marginAccount));
    }

    function verifyMarginOnPerp(
        address marginAccount,
        bytes32 marketKey,
        int256 expectedMargin
    ) public {
        int256 margin = fetchMargin(marginAccount, marketKey);
        assertEq(margin, expectedMargin, "margin does not match");
    }

    function fetchPosition(
        address marginAccount,
        bytes32 marketKey
    ) public returns (int256 positionSize, int256 positionOpenNotional) {
        address baseToken = contracts.marketManager.getMarketBaseToken(
            marketKey
        );
        int256 marketSize = IAccountBalance(perpAccountBalance)
            .getTakerPositionSize(marginAccount, baseToken);
        int256 marketOpenNotional = IAccountBalance(perpAccountBalance)
            .getTotalOpenNotional(marginAccount, baseToken);
        positionSize = marketSize;
        positionOpenNotional = -marketOpenNotional;
    }

    function verifyPositionSize(
        address marginAccount,
        bytes32 marketKey,
        int256 expectedPositionSize
    ) public {
        (
            int256 marketPositionSize,
            int256 marketPositionNotional
        ) = fetchPosition(marginAccount, marketKey);
        assertEq(
            marketPositionSize,
            expectedPositionSize,
            "expectedPositionSize not equal to chronux position size"
        );
    }

    function verifyPositionNotional(
        address marginAccount,
        bytes32 marketKey,
        int256 expectedPositionNotional
    ) public {
        (
            int256 marketPositionSize,
            int256 marketPositionNotional
        ) = fetchPosition(marginAccount, marketKey);
        assertApproxEqAbs(
            expectedPositionNotional,
            marketPositionNotional,
            DUST_THRESHOLD,
            "Perp position notional does not match"
        );
    }

    function updateAndVerifyPositionSize(
        address trader,
        bytes32 marketKey,
        int256 deltaPositionSize,
        bool shouldFail,
        bytes memory reason
    ) public {
        TradeData memory tradeData;
        tradeData.marketKey = marketKey;
        tradeData.trader = trader;
        vm.startPrank(trader);
        tradeData.marketAddress = contracts.marketManager.getMarketAddress(
            tradeData.marketKey
        );
        tradeData.marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        tradeData.baseAsset = contracts.marketManager.getMarketBaseToken(
            tradeData.marketKey
        );
        (
            tradeData.initialPositionSize,
            tradeData.initialPositionNotional
        ) = fetchPosition(tradeData.marginAccount, marketKey);

        bytes memory updatePositionData;
        if (deltaPositionSize < 0) {
            updatePositionData = abi.encodeWithSelector(
                0xb6b1b6c3,
                tradeData.baseAsset,
                true, // isShort
                true,
                -deltaPositionSize,
                0,
                type(uint256).max,
                uint160(0),
                bytes32(0)
            );
        } else {
            updatePositionData = abi.encodeWithSelector(
                0xb6b1b6c3,
                tradeData.baseAsset,
                false, // isShort
                false,
                deltaPositionSize,
                0,
                type(uint256).max,
                uint160(0),
                bytes32(0)
            );
        }
        tradeData.txDestinations = new address[](1);
        tradeData.txData = new bytes[](1);
        tradeData.txDestinations[0] = tradeData.marketAddress;
        tradeData.txData[0] = updatePositionData;
        // check event for position opened on our side.

        if (shouldFail) {
            // (
            //     tradeData.finalPositionSize,
            //     tradeData.finalPositionNotional
            // ) = fetchPosition(
            //     contracts.marginManager.getMarginAccount(tradeData.trader),
            //     tradeData.marketKey
            // );
            // vm.expectEmit(
            //     true,
            //     true,
            //     true,
            //     true,
            //     address(contracts.marginManager)
            // );
            // emit PositionAdded(
            //     tradeData.marginAccount,
            //     tradeData.marketKey,
            //     tradeData.finalPositionSize,
            //     tradeData.finalPositionNotional
            // );
            vm.expectRevert(reason);
            contracts.marginManager.updatePosition(
                tradeData.marketKey,
                tradeData.txDestinations,
                tradeData.txData
            );
        } else {
            contracts.marginManager.updatePosition(
                tradeData.marketKey,
                tradeData.txDestinations,
                tradeData.txData
            );
            verifyPositionSize(
                tradeData.marginAccount,
                tradeData.marketKey,
                deltaPositionSize + tradeData.initialPositionSize
            );
        }

        vm.stopPrank();
    }

    function updateAndVerifyPositionNotional(
        address trader,
        bytes32 marketKey,
        int256 deltaPositionNotional,
        bool shouldFail,
        bytes memory reason
    ) public {
        TradeData memory tradeData;
        tradeData.marketKey = marketKey;
        tradeData.trader = trader;
        vm.startPrank(trader);
        tradeData.marketAddress = contracts.marketManager.getMarketAddress(
            tradeData.marketKey
        );
        tradeData.marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        tradeData.baseAsset = contracts.marketManager.getMarketBaseToken(
            tradeData.marketKey
        );
        (
            tradeData.initialPositionSize,
            tradeData.initialPositionNotional
        ) = fetchPosition(tradeData.marginAccount, marketKey);

        bytes memory openPositionData;
        if (deltaPositionNotional < 0) {
            openPositionData = abi.encodeWithSelector(
                0xb6b1b6c3,
                tradeData.baseAsset,
                true, // isShort
                false,
                -deltaPositionNotional,
                0,
                type(uint256).max,
                uint160(0),
                bytes32(0)
            );
        } else {
            openPositionData = abi.encodeWithSelector(
                0xb6b1b6c3,
                tradeData.baseAsset,
                false, // isShort
                true,
                deltaPositionNotional,
                0,
                type(uint256).max,
                uint160(0),
                bytes32(0)
            );
        }

        tradeData.txDestinations = new address[](1);
        tradeData.txData = new bytes[](1);
        tradeData.txDestinations[0] = tradeData.marketAddress;
        tradeData.txData[0] = openPositionData;
        // check event for position opened on our side.

        if (shouldFail) {
            // (
            //     tradeData.finalPositionSize,
            //     tradeData.finalPositionNotional
            // ) = fetchPosition(
            //     contracts.marginManager.getMarginAccount(tradeData.trader),
            //     tradeData.marketKey
            // );
            // vm.expectEmit(
            //     true,
            //     true,
            //     true,
            //     true,
            //     address(contracts.marginManager)
            // );
            // emit PositionAdded(
            //     tradeData.marginAccount,
            //     tradeData.marketKey,
            //     tradeData.finalPositionSize,
            //     tradeData.finalPositionNotional
            // );
            vm.expectRevert(reason);
            contracts.marginManager.updatePosition(
                tradeData.marketKey,
                tradeData.txDestinations,
                tradeData.txData
            );
        }
        if (!shouldFail) {
            contracts.marginManager.updatePosition(
                tradeData.marketKey,
                tradeData.txDestinations,
                tradeData.txData
            );
            verifyPositionNotional(
                tradeData.marginAccount,
                tradeData.marketKey,
                deltaPositionNotional + tradeData.initialPositionNotional
            );
        }
        vm.stopPrank();
    }

    function prepareMarginTransfer(
        address trader,
        bytes32 marketKey,
        uint256 deltaMarginX18
    ) public {
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        uint256 tokenBalanceUsdcX18 = IERC20(usdc)
            .balanceOf(marginAccount)
            .convertTokenDecimals(6, 18);
        //TODO- Will work till susd == usdc == 1 use exchange quote price later.
        if (deltaMarginX18 > tokenBalanceUsdcX18) {
            uint256 borrowNeedX18 = deltaMarginX18 - tokenBalanceUsdcX18;
            contracts.marginManager.borrowFromVault(
                borrowNeedX18.convertTokenDecimals(18, 6)
            );
        }
    }

    // send margin in 6 decimals.
    function updateAndVerifyMargin(
        address trader,
        bytes32 marketKey,
        int256 margin,
        bool shouldFail,
        bytes memory reason
    ) public {
        int256 marginX18 = margin.convertTokenDecimals(6, 18);
        int256 marginX18Value = contracts.priceOracle.convertToUSD(
            marginX18,
            usdc
        );
        vm.startPrank(trader);
        address marketAddress = contracts.marketManager.getMarketAddress(
            marketKey
        );
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        address[] memory destinations = new address[](2);
        bytes[] memory data = new bytes[](2);
        destinations[0] = usdc;
        destinations[1] = perpVault;
        int256 currentMargin = fetchMargin(marginAccount, marketKey);
        int256 freeCollateralPerp = int256(
            IVault(perpVault).getFreeCollateral(marginAccount)
        );
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            perpVault,
            margin
        );
        data[1] = abi.encodeWithSignature(
            "deposit(address,uint256)",
            usdc,
            margin
        );
        if (shouldFail) {
            vm.expectRevert(reason);
            contracts.marginManager.updatePosition(
                marketKey,
                destinations,
                data
            );
        } else {
            if (margin > 0) {
                prepareMarginTransfer(trader, marketKey, uint256(marginX18));
                data[0] = abi.encodeWithSignature(
                    "approve(address,uint256)",
                    perpVault,
                    margin
                );
                data[1] = abi.encodeWithSignature(
                    "deposit(address,uint256)",
                    usdc,
                    margin
                );
                vm.expectEmit(
                    true,
                    true,
                    true,
                    true,
                    address(contracts.marginManager)
                );
                emit MarginTransferred(
                    marginAccount,
                    marketKey,
                    usdc,
                    marginX18,
                    marginX18Value
                );
                contracts.marginManager.updatePosition(
                    marketKey,
                    destinations,
                    data
                );
                verifyMarginOnPerp(
                    marginAccount,
                    marketKey,
                    currentMargin + margin
                );
                // existing margin + delta not just margin.
            } else {
                // emit Withdrawn(usdc, marginAccount, uint256(margin));
                destinations = new address[](1);
                data = new bytes[](1);
                destinations[0] = perpVault;
                data[0] = abi.encodeWithSignature(
                    "withdraw(address,uint256)",
                    usdc,
                    margin.abs()
                );
                vm.expectEmit(
                    true,
                    true,
                    true,
                    true,
                    address(contracts.marginManager)
                );
                emit MarginTransferred(
                    marginAccount,
                    marketKey,
                    usdc,
                    marginX18,
                    marginX18Value
                );
                contracts.marginManager.updatePosition(
                    marketKey,
                    destinations,
                    data
                );
                verifyMarginOnPerp(
                    marginAccount,
                    marketKey,
                    freeCollateralPerp + margin
                );
            }
        }
        vm.stopPrank();
    }

    function closeAndVerifyPosition(address trader, bytes32 marketKey) public {
        vm.startPrank(trader);
        address marketAddress = contracts.marketManager.getMarketAddress(
            marketKey
        );
        address baseToken = contracts.marketManager.getMarketBaseToken(
            marketKey
        );
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );

        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = marketAddress;
        data[0] = abi.encodeWithSelector(
            0x00aa9a89,
            baseToken,
            0,
            0,
            type(uint256).max,
            bytes32(0)
        );
        // check event for position opened on our side.
        vm.expectEmit(true, true, true, true, address(contracts.marginManager));
        emit PositionClosed(marginAccount, marketKey);
        contracts.marginManager.closePosition(marketKey, destinations, data);
        verifyPositionNotional(marginAccount, marketKey, 0);
        vm.stopPrank();
    }

    function revertClosePosition(
        address trader,
        bytes32 marketKey,
        bytes calldata errorMessage
    ) public {
        vm.startPrank(trader);
        address marketAddress = contracts.marketManager.getMarketAddress(
            marketKey
        );
        address baseToken = contracts.marketManager.getMarketBaseToken(
            marketKey
        );
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );

        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = marketAddress;
        data[0] = abi.encodeWithSelector(
            0x00aa9a89,
            baseToken,
            0,
            0,
            type(uint256).max,
            bytes32(0)
        );
        // check event for position opened on our side.
        vm.expectRevert(errorMessage);
        contracts.marginManager.closePosition(marketKey, destinations, data);
        vm.stopPrank();
    }

    function withdrawAllMargin(address trader, address token) public {
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        vm.startPrank(marginAccount);
        IVault(perpVault).withdrawAll(token);
    }
}
