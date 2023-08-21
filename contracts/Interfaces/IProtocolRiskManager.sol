pragma solidity ^0.8.10;
import {Position, IMarginAccount} from "./IMarginAccount.sol";
import {VerifyCloseResult, VerifyTradeResult, VerifyLiquidationResult} from "./IRiskManager.sol";

interface IProtocolRiskManager {
    function decodeTxCalldata(
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] calldata data
    ) external returns (VerifyTradeResult memory result);

    function decodeClosePositionCalldata(
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] calldata data
    ) external returns (VerifyCloseResult memory result);

    // Checks if the function signatures are allowed in liquidation calls.
    function decodeAndVerifyLiquidationCalldata(
        bool isFullyLiquidatable,
        bytes32 marketKey,
        address destination,
        bytes calldata data
    ) external;

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

    function getTotalAbsOpenNotional(
        address marginAccount
    ) external view returns (uint256 openNotional);
}
