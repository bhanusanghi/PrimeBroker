pragma solidity ^0.8.10;

import {IExchange} from "./IExchange.sol";

// position openNotional should be in 18 decimal points
// position size should be in 18 decimal points
struct Position {
    address protocol;
    int256 openNotional;
    int256 size;
    uint256 orderFee; // this refers to position opening fee as seen from SNX and Perp PRMs
    uint256 lastPrice;
}

interface IMarginAccount is IExchange {
    function totalBorrowed() external view returns (uint256);

    function cumulativeIndexAtOpen() external view returns (uint256);

    function updateBorrowData(
        uint256 _totalBorrowed,
        uint256 _cumulativeIndexAtOpen
    ) external;

    // function baseToken() external returns (address);

    function approveToProtocol(address token, address protocol) external;

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

    function getPosition(
        bytes32 marketKey
    ) external view returns (Position memory);

    function totalDollarMarginInMarkets() external view returns (int256);

    function getTotalOpeningNotional(
        bytes32[] memory _allowedMarkets
    ) external view returns (int256 totalNotional);

    function existingPosition(bytes32 marketKey) external view returns (bool);

    function updateDollarMarginInMarkets(int256 transferredMargin) external;

    // function updateMarginInMarket(address market, int256 transferredMargin)
    //     external;

    function updateUnsettledRealizedPnL(int256 _realizedPnL) external;

    function execMultiTx(
        address[] calldata destinations,
        bytes[] memory dataArray
    ) external returns (bytes memory returnData);

    function addPosition(bytes32 market, Position memory position) external;

    function updatePosition(bytes32 market, Position memory position) external;

    function removePosition(bytes32 market) external;

    function getTotalOpeningAbsoluteNotional(
        bytes32[] memory _allowedMarkets
    ) external view returns (uint256 totalNotional);

    function unsettledRealizedPnL() external view returns (int256);
}
