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
    bool isFullyLiquidatable;
    address liquidator;
    uint256 liquidationPenaltyX18;
}

interface IRiskManager {
    function verifyTrade(
        IMarginAccount marginAccount,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data
    ) external returns (VerifyTradeResult memory result);

    function verifyLiquidation(
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

    function getRemainingPositionOpenNotional(
        address _marginAccount
    ) external view returns (uint256);

    function getMarketPosition(
        address _marginAccount,
        bytes32 _marketKey
    ) external view returns (Position memory marketPosition);

    function verifyClosePosition(
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
        uint256 totalBorrowedX18,
        uint256 penaltyX18
    ) external view returns (bool isBankrupt);

    function verifyBorrowLimit(
        address _marginAccount,
        uint256 newBorrowAmountX18
    ) external view;

    function getMaxBorrowLimit(
        address _marginAccount
    ) external view returns (uint256);

    function isAccountLiquidatable(
        address marginAccount
    )
        external
        view
        returns (
            bool isLiquidatable,
            bool isFullyLiquidatable,
            uint256 penalty
        );

    function isAccountHealthy(
        address marginAccount
    ) external view returns (bool isHealthy);

    function getMaintenanceMarginRequirement(
        address marginAccount
    ) external view returns (uint256);

    function getHealthyMarginRequirement(
        address marginAccount
    ) external view returns (uint256);

    function getAccountValue(
        address marginAccount
    ) external view returns (uint256);

    function getRemainingBorrowLimit(
        address _marginAccount
    ) external view returns (uint256);

    function getTotalBuyingPower(
        address marginAccount
    ) external view returns (uint256);
}
