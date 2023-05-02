// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;

interface ICollateralManager {
    function addCollateral(address token, uint256 amount) external;

    function withdrawCollateral(address token, uint256 amount) external;

    function updateCollateralWeight(
        address token,
        uint256 collateralWeight
    ) external;

    function totalCollateralValue(
        address marginAccount
    ) external view returns (uint256 amount);
}
