pragma solidity ^0.8.10;

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
    function transferTokens(
        address token,
        address to,
        uint256 amount // onlyMarginManager
    ) external;
}
