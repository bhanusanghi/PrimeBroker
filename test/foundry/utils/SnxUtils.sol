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
    Contracts contracts;
    address susd = 0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9;

    constructor(Contracts _contracts) {
        contracts = _contracts;
    }

    function fetchPosition(
        address marginAccount,
        bytes32 marketKey
    ) public returns (int256 positionSize, int256 openNotional) {
        address market = contracts.marketManager.getMarketAddress(marketKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        (, , , , positionSize) = IFuturesMarket(market).positions(
            marginAccount
        );
        openNotional = (positionSize * int256(assetPrice)) / 1 ether;
        console2.log("Reached eof for fetchSNXPos");
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
        int256 positionSize
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
        vm.expectEmit(true, true, true, true, address(contracts.marginManager));
        emit PositionAdded(
            marginAccount,
            marketKey,
            positionSize,
            (positionSize * int256(assetPriceBeforeOpen)) / 1 ether // openNotional
        );

        contracts.marginManager.openPosition(marketKey, destinations, data);
        verifyPosition(marginAccount, marketKey, positionSize);
        vm.stopPrank();
    }

    function updateAndVerifyPosition(
        address trader,
        bytes32 marketKey,
        int256 positionSize
    ) public {
        vm.startPrank(trader);
        // address marginAccount = contracts.marginManager.getMarginAccount(trader);
        address marketAddress = contracts.marketManager.getMarketAddress(
            marketKey
        );
        (uint256 assetPriceBeforeUpdate, ) = IFuturesMarket(marketAddress)
            .assetPrice();
        (int256 existingSize, int256 existingNotional) = fetchPosition(
            contracts.marginManager.getMarginAccount(trader),
            marketAddress
        );
        bytes memory updatePositionData = abi.encodeWithSignature(
            "modifyPositionWithTracking(int256,bytes32)",
            positionSize,
            keccak256("GigabrainMarginAccount")
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = marketAddress;
        data[0] = updatePositionData;
        // check event for position opened on our side.
        vm.expectEmit(true, true, true, true, address(contracts.marginManager));
        console2.log("emitting position updated");
        console2.logInt(positionSize);
        console2.logInt(existingSize);
        console2.logInt(existingNotional);
        console2.logInt(positionSize + existingSize);
        console2.log(
            "emitting position updated 2 - ",
            (positionSize * int256(assetPriceBeforeUpdate)) /
                1 ether +
                existingNotional
        );
        emit PositionUpdated(
            contracts.marginManager.getMarginAccount(trader),
            marketKey,
            positionSize + existingSize,
            (positionSize * int256(assetPriceBeforeUpdate)) /
                1 ether +
                existingNotional
        );

        contracts.marginManager.updatePosition(marketKey, destinations, data);
        verifyPosition(
            contracts.marginManager.getMarginAccount(trader),
            marketKey,
            positionSize + existingSize
        );
        console2.log("updated position");
        vm.stopPrank();
    }

    // =========================================== Margin Related Utils ===========================================
    function fetchMargin(
        address marginAccount,
        bytes32 marketKey
    ) public returns (int256 margin) {
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
        int256 margin
    ) public {
        vm.startPrank(trader);
        address marketAddress = contracts.marketManager.getMarketAddress(
            marketKey
        );
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
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
        vm.expectEmit(true, true, true, true, address(contracts.marginManager));
        uint256 marginDollarValue = margin.convertTokenDecimals(
            18,
            ERC20(contracts.vault.asset()).decimals()
        );
        emit MarginTransferred(
            marginAccount,
            marketKey,
            susd,
            margin,
            marginDollarValue
        );

        contracts.marginManager.openPosition(marketKey, destinations, data);
        verifyMargin(marginAccount, marketKey, margin);
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
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
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
