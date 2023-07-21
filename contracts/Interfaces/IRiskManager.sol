pragma solidity ^0.8.10;
import {Position, IMarginAccount} from "./IMarginAccount.sol";

struct VerifyTradeResult {
    int256 marginDelta;
    int256 marginDeltaDollarValue;
    Position position;
    address tokenOut;
}
struct VerifyCloseResult {
    // bool isValid;
    // int256 finalPnL; // will fill this after tx execution
    int256 closingPrice;
    address marginToken;
    // int256 orderFee;
    // int256 fundingFee;
    // int256 positionSize;
    // int256 positionNotional;
}
struct VerifyLiquidationResult {
    int256 marginDelta;
    bool isFullLiquidation;
    address liquidator;
    address liquidationPenalty;
}

interface IRiskManager {
    function verifyTrade(
        IMarginAccount marginAccount,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data
    ) external returns (VerifyTradeResult memory result);

    function liquidate(
        IMarginAccount marginAccount,
        bytes32[] memory marketKeys,
        address[] memory destinations,
        bytes[] calldata data
    ) external returns (VerifyLiquidationResult memory result);

    function initialMarginFactor() external returns (uint256);

    // @note This finds all the realized accounting parameters at the TPP and returns deltaMargin representing the change in margin.
    //realized PnL, Order Fee, settled funding fee, liquidation Penalty etc. Exact parameters will be tracked in implementatios of respective Protocol Risk Managers
    // This should affect the Trader's Margin directly.
    function getCurrentDollarMarginInMarkets(
        address marginAccount
    ) external view returns (int256);

    function getUnrealizedPnL(
        address marginAccount
    ) external view returns (int256 totalUnrealizedPnL);

    function getRemainingMarginTransfer(
        address _marginAccount
    ) external view returns (uint256);

    function getRemainingPositionOpenNotional(
        address _marginAccount
    ) external view returns (uint256);

    function getMarketPosition(
        address _marginAccount,
        bytes32 _marketKey
    ) external view returns (Position memory marketPosition);

    function verifyClosePosition(
        IMarginAccount marginAcc,
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) external returns (VerifyCloseResult memory result);

    function decodeAndVerifyLiquidationCalldata(
        IMarginAccount marginAcc,
        bool isFullyLiquidatable,
        bytes32[] memory marketKeys,
        address[] memory destinations,
        bytes[] calldata data
    ) external returns (VerifyLiquidationResult memory result);

    function isTraderBankrupt(
        address marginAccount,
        uint256 vaultLiability
    ) external view returns (bool isBankrupt);

    function getCollateralInMarkets(
        address _marginAccount
    ) external view returns (uint256 totalCollateralValue);

    function verifyBorrowLimit(
        address _marginAccount,
        uint256 newBorrowAmountX18
    ) external view;

    function getMaxBorrowLimit(
        address _marginAccount
    ) external view returns (uint256);

    function isAccountLiquidatable(
        address marginAccount
    ) external view returns (bool isLiquidatable, bool isFullyLiquidatable);

    function isAccountHealthy(
        address marginAccount
    ) external view returns (bool isHealthy);

    function getMinimumMaintenanceMarginRequirement(
        address marginAccount
    ) external view returns (uint256);

    function getAccountValue(
        address marginAccount
    ) external view returns (uint256);
}
