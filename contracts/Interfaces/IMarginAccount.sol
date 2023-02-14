pragma solidity ^0.8.10;

// position openNotional should be in 18 decimal points
// position size should be in 18 decimal points
struct Position {
    address protocol;
    int256 openNotional;
    int256 size;
    uint256 fee; // this refers to position opening fee as seen from SNX and Perp PRMs
}

interface IMarginAccount {
    function underlyingToken() external view returns (address);

    function totalBorrowed() external view returns (uint256);

    function cumulativeIndexAtOpen() external view returns (uint256);

    function updateBorrowData(
        uint256 _totalBorrowed,
        uint256 _cumulativeIndexAtOpen
    ) external;

    function baseToken() external returns (address);

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

    function executeTx(address destination, bytes memory data)
        external
        returns (bytes memory);

    function getPositionOpenNotional(bytes32 marketKey)
        external
        view
        returns (int256);

    function totalMarginInMarkets() external view returns (int256);

    function getTotalOpeningNotional(bytes32[] memory _allowedMarkets)
        external
        view
        returns (int256 totalNotional);
}
