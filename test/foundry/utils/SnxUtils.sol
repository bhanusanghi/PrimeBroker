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

// import {Contracts, OpenPositionParams, PositionData, PerpTradingData, MarginAccountData, SNXTradingData, } from "../IEvents.sol";

contract SnxUtils is Test, IEvents {
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    Contracts contracts;
    address susd = 0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9;

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
        (, , uint256 remainingMargin, , ) = IFuturesMarket(market).positions(
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

    // send margin in 18 decimals.
    function updateAndVerifyMargin(
        address trader,
        bytes32 marketKey,
        int256 deltaMargin,
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
            deltaMargin
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
            vm.expectEmit(
                true,
                true,
                true,
                true, // there is a diff of 1 wei in the value due to rounding.
                address(contracts.marginManager)
            );
            int256 marginDollarValue = deltaMargin.convertTokenDecimals(
                18,
                ERC20(contracts.vault.asset()).decimals()
            );
            emit MarginTransferred(
                marginAccount,
                marketKey,
                susd,
                deltaMargin,
                marginDollarValue
            );
            contracts.marginManager.openPosition(marketKey, destinations, data);
            verifyMargin(
                marginAccount,
                marketKey,
                deltaMargin + existingMargin
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
        vm.expectRevert(bytes("Extra Transfer not allowed"));
        contracts.marginManager.openPosition(marketKey, destinations, data);
        vm.stopPrank();
    }
}
