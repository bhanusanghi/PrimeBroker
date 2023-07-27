// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;
import {Test} from "forge-std/Test.sol";
import {ICircuitBreaker} from "../../../contracts/Interfaces/SNX/ICircuitBreaker.sol";
import {SettlementTokenMath} from "../../../contracts/Libraries/SettlementTokenMath.sol";
import {IAddressResolver} from "../../../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IMarginAccount} from "../../../contracts/Interfaces/IMarginAccount.sol";
import {IFuturesMarketManager} from "../../../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
import {IFuturesMarket} from "../../../contracts/Interfaces/SNX/IFuturesMarket.sol";
import {IFuturesMarketBaseTypes} from "../../../contracts/Interfaces/SNX/IFuturesMarketBaseTypes.sol";
import {IFuturesMarketBaseTypes} from "../../../contracts/Interfaces/SNX/IFuturesMarketBaseTypes.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IFuturesMarketSettings} from "../../../contracts/Interfaces/SNX/IFuturesMarketSettings.sol";
import {SettlementTokenMath} from "../../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MarginAccount} from "../../../contracts/MarginAccount/MarginAccount.sol";
import {Position} from "../../../contracts/Interfaces/IMarginAccount.sol";
import {IEvents} from "../IEvents.sol";
import "forge-std/console2.sol";

contract SnxUtils is Test, IEvents {
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SignedMath for int256;
    Contracts contracts;
    address susd = 0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9;
    address usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;

    constructor(Contracts memory _contracts) {
        contracts = _contracts;
    }

    function fetchPosition(
        address marginAccount,
        bytes32 marketKey
    ) public view returns (int256 positionSize, int256 openNotional) {
        address market = contracts.marketManager.getMarketAddress(marketKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        (, , , , positionSize) = IFuturesMarket(market).positions(
            marginAccount
        );
        openNotional = (positionSize * int256(assetPrice)) / 1 ether;
    }

    function verifyPosition(
        address marginAccount,
        bytes32 marketKey,
        int256 expectedPositionSize
    ) public {
        Position memory positionChronux = MarginAccount(marginAccount)
            .getPosition(marketKey);
        (int256 snxPositionSize, int256 snxPositionNotional) = fetchPosition(
            marginAccount,
            marketKey
        );
        assertEq(positionChronux.size, expectedPositionSize);
        assertEq(positionChronux.size, snxPositionSize);
    }

    function borrowAssets(uint256 amount) public {}

    function repayAssets(uint256 amount) public {
        contracts.marginManager.repayVault(amount);
    }

    function swapAssets(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) public returns (uint256 amountOut) {
        amountOut = contracts.marginManager.swapAsset(
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut
        );
    }

    function addAndVerifyPosition(
        address trader,
        bytes32 marketKey,
        int256 positionSize,
        bool shouldFail,
        bytes memory reason
    ) public {
        vm.startPrank(trader);
        address marketAddress = contracts.marketManager.getMarketAddress(
            marketKey
        );
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        (uint256 assetPriceBeforeOpen, ) = IFuturesMarket(marketAddress)
            .assetPrice();
        bytes memory openPositionData = abi.encodeWithSignature(
            "modifyPositionWithTracking(int256,bytes32)",
            positionSize,
            keccak256("GigabrainMarginAccount")
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = marketAddress;
        data[0] = openPositionData;
        // check event for position opened on our side.
        if (!shouldFail) {
            vm.expectEmit(
                true,
                true,
                true,
                false, // potential difference of 1 wei in value because of rounding
                address(contracts.marginManager)
            );
            emit PositionAdded(
                marginAccount,
                marketKey,
                positionSize,
                (positionSize * int256(assetPriceBeforeOpen)) / 1 ether // openNotional
            );
            contracts.marginManager.openPosition(marketKey, destinations, data);
            verifyPosition(marginAccount, marketKey, positionSize);
        } else {
            vm.expectRevert(reason);
            contracts.marginManager.openPosition(marketKey, destinations, data);
        }
        vm.stopPrank();
    }

    function updateAndVerifyPositionSize(
        address trader,
        bytes32 marketKey,
        int256 positionSize,
        bool shouldFail,
        bytes memory reason
    ) public {
        TradeData memory tradeData;
        tradeData.marketKey = marketKey;
        tradeData.trader = trader;
        vm.startPrank(trader);
        // address marginAccount = contracts.marginManager.getMarginAccount(trader);
        tradeData.marketAddress = contracts.marketManager.getMarketAddress(
            marketKey
        );
        tradeData.marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        (uint256 assetPriceBeforeUpdate, ) = IFuturesMarket(
            tradeData.marketAddress
        ).assetPrice();
        (
            tradeData.initialPositionSize,
            tradeData.initialPositionNotional
        ) = fetchPosition(tradeData.marginAccount, marketKey);
        bytes memory updatePositionData = abi.encodeWithSignature(
            "modifyPositionWithTracking(int256,bytes32)",
            positionSize,
            keccak256("GigabrainMarginAccount")
        );
        tradeData.txDestinations = new address[](1);
        tradeData.txData = new bytes[](1);
        tradeData.txDestinations[0] = tradeData.marketAddress;
        tradeData.txData[0] = updatePositionData;
        // check event for position opened on our side.

        if (!shouldFail) {
            vm.expectEmit(
                true,
                true,
                true,
                false,
                address(contracts.marginManager)
            );
            emit PositionUpdated(
                tradeData.marginAccount,
                tradeData.marketKey,
                positionSize + tradeData.initialPositionSize,
                ((positionSize * int256(assetPriceBeforeUpdate)) / 1 ether) +
                    tradeData.initialPositionNotional
            );
            contracts.marginManager.updatePosition(
                tradeData.marketKey,
                tradeData.txDestinations,
                tradeData.txData
            );
            verifyPosition(
                tradeData.marginAccount,
                marketKey,
                positionSize + tradeData.initialPositionSize
            );
        } else {
            vm.expectRevert(reason);
            contracts.marginManager.updatePosition(
                tradeData.marketKey,
                tradeData.txDestinations,
                tradeData.txData
            );
        }
        vm.stopPrank();
    }

    // =========================================== Margin Related Utils ===========================================
    function fetchMargin(
        address marginAccount,
        bytes32 marketKey
    ) public view returns (int256 margin) {
        address market = contracts.marketManager.getMarketAddress(marketKey);
        (uint256 remainingMargin, ) = IFuturesMarket(market).remainingMargin(
            marginAccount
        );
        margin = int256(remainingMargin);
    }

    function verifyMargin(
        address marginAccount,
        bytes32 marketKey,
        int256 expectedMargin
    ) public {
        int256 margin = fetchMargin(marginAccount, marketKey);
        assertEq(margin, expectedMargin);
    }

    // call with an active trader prank
    function prepareMarginTransfer(
        address trader,
        bytes32 marketKey,
        uint256 deltaMarginX18
    ) public {
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        uint256 tokenBalanceSusdX18 = IERC20(susd).balanceOf(marginAccount);
        uint256 tokenBalanceUsdcX18 = IERC20(usdc)
            .balanceOf(marginAccount)
            .convertTokenDecimals(6, 18);
        //TODO- Will work till susd == usdc == 1 use exchange quote price later.
        if (deltaMarginX18 > tokenBalanceSusdX18) {
            uint256 susdDiffX18 = deltaMarginX18 - tokenBalanceSusdX18;
            uint256 borrowNeedX18 = susdDiffX18 -
                tokenBalanceUsdcX18 +
                100 ether;
            contracts.marginManager.borrowFromVault(
                borrowNeedX18.convertTokenDecimals(18, 6)
            );
            uint256 tokenOut = contracts.marginManager.swapAsset(
                usdc,
                susd,
                (susdDiffX18 + 100 ether).convertTokenDecimals(18, 6),
                susdDiffX18
            );
        }
    }

    // send margin in 18 decimals.
    function updateAndVerifyMargin(
        address trader,
        bytes32 marketKey,
        int256 deltaMarginX18,
        bool shouldFail,
        bytes memory reason
    ) public {
        vm.startPrank(trader);
        address marketAddress = contracts.marketManager.getMarketAddress(
            marketKey
        );
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        int256 existingMargin = fetchMargin(marginAccount, marketKey);

        bytes memory transferMarginData = abi.encodeWithSignature(
            "transferMargin(int256)",
            deltaMarginX18
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = marketAddress;
        data[0] = transferMarginData;
        // check event for position opened on our side.
        if (shouldFail) {
            vm.expectRevert(reason);
            contracts.marginManager.openPosition(marketKey, destinations, data);
        } else {
            if (deltaMarginX18 > 0) {
                prepareMarginTransfer(trader, marketKey, deltaMarginX18.abs());
            }
            vm.expectEmit(
                true,
                true,
                true,
                true, // there is a diff of 1 wei in the value due to rounding.
                address(contracts.marginManager)
            );
            emit MarginTransferred(
                marginAccount,
                marketKey,
                susd,
                deltaMarginX18,
                deltaMarginX18
            );
            contracts.marginManager.openPosition(marketKey, destinations, data);
            verifyMargin(
                marginAccount,
                marketKey,
                deltaMarginX18 + existingMargin
            );
        }
        vm.stopPrank();
    }

    function verifyExcessMarginRevert(
        address trader,
        bytes32 marketKey,
        int256 margin
    ) public {
        vm.startPrank(trader);
        address marketAddress = contracts.marketManager.getMarketAddress(
            marketKey
        );
        bytes memory transferMarginData = abi.encodeWithSignature(
            "transferMargin(int256)",
            margin
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = marketAddress;
        data[0] = transferMarginData;
        // check event for position opened on our side.
        vm.expectRevert(bytes("Borrow limit exceeded"));
        contracts.marginManager.openPosition(marketKey, destinations, data);
        vm.stopPrank();
    }

    function closeAndVerifyPosition(address trader, bytes32 marketKey) public {
        vm.startPrank(trader);
        address marketAddress = contracts.marketManager.getMarketAddress(
            marketKey
        );
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        bytes memory closePositionData = abi.encodeWithSignature(
            "closePositionWithTracking(bytes32)",
            keccak256("GigabrainMarginAccount")
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = marketAddress;
        data[0] = closePositionData;
        // check event for position opened on our side.
        vm.expectEmit(
            true,
            true,
            true,
            false, // there is a diff of 1 wei in the value due to rounding.
            address(contracts.marginManager)
        );
        emit PositionClosed(marginAccount, marketKey);
        contracts.marginManager.closePosition(marketKey, destinations, data);
        verifyPosition(marginAccount, marketKey, 0);
        vm.stopPrank();
    }
}
