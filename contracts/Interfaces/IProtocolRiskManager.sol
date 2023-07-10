pragma solidity ^0.8.10;
import {Position, IMarginAccount} from "./IMarginAccount.sol";
import {VerifyCloseResult, VerifyTradeResult, VerifyLiquidationResult} from "./IRiskManager.sol";

interface IProtocolRiskManager {
    // mapping(bytes4=>string) public abiStrings;
    // bytes4[] public supportedFunctions;

    // function getPositionPnL(address marginAccount) external returns (int256);
    function setPriceOracle(address oracle) external;

    function decodeTxCalldata(
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] calldata data
    ) external returns (VerifyTradeResult memory result);

    function decodeClosePositionCalldata(
        IMarginAccount marginAcc,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] calldata data
    ) external returns (VerifyCloseResult memory result);

    // Checks if the function signatures are allowed in liquidation calls.
    function decodeAndVerifyLiquidationCalldata(
        IMarginAccount marginAcc,
        bool isFullyLiquidatable,
        bytes32 marketKey,
        address destination,
        bytes calldata data
    ) external returns (VerifyLiquidationResult memory result);

    function toggleAddressWhitelisting(
        address contractAddress,
        bool isAllowed
    ) external;

    function getUnrealizedPnL(
        address marginAccount
    ) external view returns (int256);

    function getDollarMarginInMarkets(
        address marginAccount
    ) external view returns (int256);

    function getMarginToken() external view returns (address);

    function getMarketPosition(
        address marginAccount,
        bytes32 marketKey
    ) external view returns (Position memory position);
}
