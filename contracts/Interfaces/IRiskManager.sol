pragma solidity ^0.8.10;
import {Position} from "./IMarginAccount.sol";

struct VerifyTradeResult {
    address protocolAddress;
    int256 marginDelta;
    int256 marginDeltaDollarValue;
    Position position;
    address tokenOut;
}

interface IRiskManager {
    function verifyTrade(
        address marginAcc,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data,
        uint256 interestAccrued
    ) external returns (VerifyTradeResult memory result);

    function initialMarginFactor() external returns (uint256);

    function setPriceOracle(address oracle) external;

    // @note This finds all the realized accounting parameters at the TPP and returns deltaMargin representing the change in margin.
    //realized PnL, Order Fee, settled funding fee, liquidation Penalty etc. Exact parameters will be tracked in implementatios of respective Protocol Risk Managers
    // This should affect the Trader's Margin directly.
    function getRealizedPnL(address marginAccount) external returns (int256);

    function getUnrealizedPnL(address marginAccount)
        external
        returns (int256 totalUnrealizedPnL);

    // @note This finds all the realized accounting parameters at the TPP and returns deltaMargin representing the change in margin.
    //realized PnL, Order Fee, settled funding fee, liquidation Penalty etc. Exact parameters will be tracked in implementatios of respective Protocol Risk Managers
    // This should affect the Trader's Margin directly.
    function settleRealizedAccounting(address marginAccount) external;

    //@note This returns the total deltaMargin comprising unsettled accounting on TPPs
    // ex -> position's PnL. pending Funding Fee etc. refer to implementations for exact params being being settled.
    // This should effect the Buying Power of account.
    function getUnsettledAccounting(address marginAccount) external;
}
