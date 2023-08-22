pragma solidity ^0.8.10;

// position openNotional should be in 18 decimal points
// position size should be in 18 decimal points
struct Position {
    int256 openNotional;
    int256 size;
    uint256 orderFee; // this refers to position opening fee as seen from SNX and Perp PRMs
    uint256 lastPrice;
}

interface IMarginAccount {
    function totalBorrowed() external view returns (uint256);

    function cumulativeIndexAtOpen() external view returns (uint256);

    function addCollateral(
        address from,
        address token,
        uint256 amount
    ) external;

    function transferTokens(
        address token,
        address to,
        uint256 amount // onlyMarginManager
    ) external;

    function executeTx(
        address destination,
        bytes memory data
    ) external returns (bytes memory);

    function existingPosition(bytes32 marketKey) external view returns (bool);

    // function updateMarginInMarket(address market, int256 transferredMargin)
    //     external;
    function execMultiTx(
        address[] calldata destinations,
        bytes[] memory dataArray
    ) external returns (bytes memory returnData);

    function updatePosition(bytes32 market) external;

    function removePosition(bytes32 market) external;

    // function getTotalOpeningAbsoluteNotional()
    //     external
    //     view
    //     returns (uint256 totalNotional);

    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    function isActivePosition(bytes32 market) external view returns (bool);

    function setTokenAllowance(
        address token,
        address spender,
        uint256 amount
    ) external;

    function getInterestAccruedX18() external view returns (uint256);

    function increaseDebt(uint256 amount) external;

    function decreaseDebt(uint256 amount) external;
}
