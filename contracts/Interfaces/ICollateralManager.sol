// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;

interface ICollateralManager {
    function addCollateral(
        address token,
        uint256 amount,
        address marginAccount
    ) external;

    function withdrawCollateral(
        address token,
        uint256 amount,
        address marginAccount
    ) external;

    function updateCollateralWeight(
        address token,
        uint256 allowlistIndex,
        uint256 collateralWeight
    ) external;

    function totalCollateralValue(address marginAccount)
        external
        returns (uint256 amount);
}
