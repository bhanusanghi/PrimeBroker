pragma solidity ^0.8.10;

interface IPriceOracle {
    function convertToUSD(int256 amount, address token)
        external
        view
        returns (int256);

    function convertFromUSD(uint256 amount, address token)
        external
        view
        returns (uint256);

    function convert(
        uint256 amount,
        address tokenFrom,
        address tokenTo
    ) external view returns (uint256);

    function fastCheck(
        uint256 amountFrom,
        address tokenFrom,
        uint256 amountTo,
        address tokenTo
    ) external view returns (uint256 collateralFrom, uint256 collateralTo);

    function priceFeeds(address token) external view returns (address);
}
