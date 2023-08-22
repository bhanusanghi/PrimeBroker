pragma solidity ^0.8.10;

interface IMarginManager {
    event MarginAccountOpened(address indexed trader, address indexed marginAccount);
    event MarginAccountLiquidated(address indexed trader, address indexed marginAccount);
    event MarginAccountClosed(address indexed trader, address indexed marginAccount);
    event MarginTransferred(
        address indexed marginAccount,
        bytes32 indexed marketKey,
        address indexed tokenOut,
        int256 marginTokenAmountX18,
        int256 marginValueX18
    );

    // marginAccount, protocol, assetOut, size, openNotional

    event PositionUpdated( //final size
        // final openNotional
        // uint256 lastPrice,
        // int256 deltaSize,
        // int256 deltaNotional,
    address indexed marginAccount, bytes32 indexed marketKey, int256 size, int256 openNotional);
    event PositionClosed(address indexed marginAccount, bytes32 indexed marketKey);

    event AccountLiquidated(address indexed marginAccount, address indexed liquidator, uint256 liquidationPenaltyX18);
    // bool hasBadDebt,
    // uint256 badDebtAmount

    function getMarginAccount(address trader) external view returns (address);

    function setRiskManager(address _riskmgr) external;

    function setVault(address _vault) external;

    function openMarginAccount() external returns (address);

    function drainAllMarginAccounts(address _token) external;

    function closeMarginAccount(address marginAccount) external;

    function updatePosition(bytes32 marketKey, address[] calldata destinations, bytes[] calldata data) external;

    function closePosition(bytes32 marketKey, address[] calldata destinations, bytes[] calldata data) external;

    function liquidate(
        address trader,
        bytes32[] calldata marketKeys,
        address[] calldata destinations,
        bytes[] calldata data
    ) external;

    function borrowFromVault(uint256 amount) external;

    function repayVault(uint256 amount) external;

    function swapAsset(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 amountOut);
}
