// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;

interface ICollateralManager {
    function depositCollateral(address token, uint256 amount) external;

    function withdrawCollateral(address token, uint256 amount) external;

    function updateCollateralWeight(
        address token,
        uint256 collateralWeight
    ) external;

    function totalCollateralValue(
        address marginAccount
    ) external view returns (uint256 amount);

    function whitelistCollateral(
        address _allowed,
        uint256 _collateralWeight
    ) external;

    function getFreeCollateralValue(
        address _marginAccount
    ) external returns (uint256);

    function getCollateralValueInMarginAccount(
        address _marginAccount
    ) external view returns (uint256 totalAmount);

    function collateralWeight(address) external view returns (uint256);

    function getAllCollateralTokens() external view returns (address[] memory);

    function isAllowedCollateral(address) external view returns (bool);
}
