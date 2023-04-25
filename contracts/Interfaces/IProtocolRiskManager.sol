pragma solidity ^0.8.10;
import {Position} from "./IMarginAccount.sol";

interface IProtocolRiskManager {
    // mapping(bytes4=>string) public abiStrings;
    // bytes4[] public supportedFunctions;

    // function getPositionPnL(address marginAccount) external returns (int256);

    function verifyTrade(
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] calldata data
    )
        external
        returns (
            int256 amount,
            Position memory deltaPosition
            // uint256 fee
        );

    function verifyClose(
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] calldata data
    ) external returns (int256 amount, int256 totalPosition, uint256 fee);

    function toggleAddressWhitelisting(
        address contractAddress,
        bool isAllowed
    ) external;

    function getUnrealizedPnL(address marginAccount) external returns (int256);

    // @note This finds all the realized accounting parameters at the TPP and returns deltaMargin representing the change in margin.
    //realized PnL, Order Fee, settled funding fee, liquidation Penalty etc. Exact parameters will be tracked in implementatios of respective Protocol Risk Managers
    // This should affect the Trader's Margin directly.
    function settleRealizedAccounting(address marginAccount) external;

    //@note This returns the total deltaMargin comprising unsettled accounting on TPPs
    // ex -> position's PnL. pending Funding Fee etc. refer to implementations for exact params being being settled.
    // This should effect the Buying Power of account.
    function getUnsettledAccounting(address marginAccount) external;

    function getDollarMarginInMarkets(
        address marginAccount
    ) external returns (int256);

    function getMarginToken() external view returns (address);

    function getMarketPosition(
        address marginAccount,
        bytes32 marketKey
    ) external view returns (Position memory position);
}
