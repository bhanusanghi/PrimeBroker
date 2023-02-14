pragma solidity ^0.8.10;

// position openNotional should be in 18 decimal points
// position size should be in 18 decimal points
struct Position {
    address protocol;
    int256 openNotional;
    int256 size;
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

    function addCollateral(
        address from,
        address token,
        uint256 amount
    ) external;

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
