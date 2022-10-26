pragma solidity ^0.8.10;

interface IMarginAccount {
    function underlyingToken() external view returns (address);

    function totalBorrowed() external view returns (int256);

    function cumulativeIndexAtOpen() external view returns (uint256);

    function updateBorrowData(
        int256 _totalBorrowed,
        uint256 _cumulativeIndexAtOpen
    ) external;

    function baseToken() external returns (address);
    function addCollateral(address from, address token, uint256 amount) external;
}
