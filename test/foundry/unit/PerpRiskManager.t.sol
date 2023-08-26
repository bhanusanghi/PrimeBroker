pragma solidity ^0.8.10;

import "forge-std/console2.sol";

import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {BaseSetup} from "../BaseSetup.sol";
import {SnxUtils} from "../utils/SnxUtils.sol";
import {PerpfiUtils} from "../utils/PerpfiUtils.sol";
import {ChronuxUtils} from "../utils/ChronuxUtils.sol";
import {IFuturesMarket} from "../../../contracts/Interfaces/SNX/IFuturesMarket.sol";
// import {IRiskManager, VerifyTradeResult} from "../../../contracts/Interfaces/IRiskManager.sol";
import {Utils} from "../utils/Utils.sol";

contract PerpRiskManagerTest is BaseSetup {
    using SafeMath for uint256;
    using SafeMath for uint128;
    using Math for uint256;
    using Math for int256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    SnxUtils snxUtils;
    PerpfiUtils perpfiUtils;
    ChronuxUtils chronuxUtils;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("ARCHIVE_NODE_URL_L2"), 71255016);
        vm.selectFork(forkId);
        // need to be done in this order only.
        utils = new Utils();
        setupPrmFixture();
        chronuxUtils = new ChronuxUtils(contracts);
        snxUtils = new SnxUtils(contracts);
        perpfiUtils = new PerpfiUtils(contracts);
    }

    function testRevertInvalidDestination() public {
        bytes memory openPositionData = abi.encodeWithSelector(
            0xb6b1b6c3,
            perpAaveMarket,
            true, // isShort
            false,
            200,
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = perpAccountBalance;
        data[0] = openPositionData;
        vm.expectRevert("PRM: Calling non whitelisted contract");
        contracts.perpfiRiskManager.decodeTxCalldata(perpAaveKey, destinations, data);
    }

    function testRevertInvalidFunSig() public {
        bytes memory openPositionData = abi.encodeWithSelector(
            0xb6b1b3c3,
            perpAaveMarket,
            true, // isShort
            false,
            200,
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = perpClearingHouse;
        data[0] = openPositionData;
        vm.expectRevert("PRM: Unsupported Function call");
        contracts.perpfiRiskManager.decodeTxCalldata(perpAaveKey, destinations, data);
    }

    function testRevertInvalidBaseToken() public {
        bytes memory openPositionData = abi.encodeWithSelector(
            0xb6b1b6c3,
            perpEthMarket,
            true, // isShort
            false,
            200,
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = perpClearingHouse;
        data[0] = openPositionData;
        vm.expectRevert("PRM: Invalid Base Token");
        contracts.perpfiRiskManager.decodeTxCalldata(perpAaveKey, destinations, data);
    }

    function testDecodeDataFailure() public {
        bytes memory openPositionData = abi.encodeWithSelector(
            0xb6b1b6c3,
            perpAaveMarket,
            true,
            1 ether, // wrong data type
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = perpClearingHouse;
        data[0] = openPositionData;
        vm.expectRevert();
        contracts.perpfiRiskManager.decodeTxCalldata(perpAaveKey, destinations, data);
    }

    function testDecodeDataFailureDataType() public {
        bytes memory openPositionData = abi.encodeWithSelector(
            0xb6b1b6c3,
            perpAaveMarket,
            true,
            false,
            0,
            type(uint256).max,
            type(uint256).max, // wrong data type
            bytes32(0)
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = perpClearingHouse;
        data[0] = openPositionData;
        vm.expectRevert();
        contracts.perpfiRiskManager.decodeTxCalldata(perpAaveKey, destinations, data);
    }

    function testRevertClosingWithInvalidFunSig() public {
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = perpClearingHouse;
        data[0] = abi.encodeWithSelector(
            0x00aa9b89, //0x00aa9a89
            perpAaveMarket,
            0,
            0,
            type(uint256).max,
            bytes32(0)
        );
        vm.expectRevert("PRM: Unsupported Function call");
        contracts.perpfiRiskManager.decodeClosePositionCalldata(perpAaveKey, destinations, data);
    }

    function testRevertClosingWithInvalidDestination() public {
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = perpEthMarket;
        data[0] = abi.encodeWithSelector(0x00aa9a89, perpAaveMarket, 0, 0, type(uint256).max, bytes32(0));
        vm.expectRevert("PRM: Calling non whitelisted contract");
        contracts.perpfiRiskManager.decodeClosePositionCalldata(perpAaveKey, destinations, data);
    }

    function testRevertClosingWithInvalidBaseToken() public {
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = perpClearingHouse;
        data[0] = abi.encodeWithSelector(
            0x00aa9a89, //
            perpEthMarket,
            0,
            0,
            type(uint256).max,
            bytes32(0)
        );
        vm.expectRevert("PRM: Invalid base token in close call");
        contracts.perpfiRiskManager.decodeClosePositionCalldata(perpAaveKey, destinations, data);
    }

    function testRevertLiquidatingWithInvalidFunSig() public {
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = perpClearingHouse;
        data[0] = abi.encodeWithSelector(
            0x00aa9b89, //0x00aa9a89
            perpAaveMarket,
            0,
            0,
            type(uint256).max,
            bytes32(0)
        );
        vm.expectRevert("PRM: Unsupported Function call");
        contracts.perpfiRiskManager.decodeClosePositionCalldata(perpAaveKey, destinations, data);
    }

    function testRevertLiquidatingWithInvalidDestination() public {
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = perpEthMarket;
        data[0] = abi.encodeWithSelector(0x00aa9a89, perpAaveMarket, 0, 0, type(uint256).max, bytes32(0));
        vm.expectRevert("PRM: Calling non whitelisted contract");
        contracts.perpfiRiskManager.decodeClosePositionCalldata(perpAaveKey, destinations, data);
    }

    function testRevertLiquidatingWithInvalidBaseToken() public {
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = perpClearingHouse;
        data[0] = abi.encodeWithSelector(
            0x00aa9a89, //
            perpEthMarket,
            0,
            0,
            type(uint256).max,
            bytes32(0)
        );
        vm.expectRevert("PRM: Invalid base token in close call");
        contracts.perpfiRiskManager.decodeClosePositionCalldata(perpAaveKey, destinations, data);
    }
}

/*
    Integration testing ->
    getUnrealizedPnL
    getCurrentDollarMarginInMarkets
    getAccruedFunding
    getMarketPosition

    Unit Testing ->
    verifyTrade with wrong data
      whitelisted addresses only
    verifyClosePosition with wrong data
    verifyLiquidation with wrong data


  */
