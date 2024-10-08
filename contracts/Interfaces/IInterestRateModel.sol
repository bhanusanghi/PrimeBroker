// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

/// @title IInterestRateModel interface
/// @dev Interface for the calculation of the interest rates
interface IInterestRateModel {
    /// @dev Calculated borrow rate based on expectedLiquidity and availableLiquidity
    /// @param expectedLiquidity Expected liquidity in the pool
    /// @param availableLiquidity Available liquidity in the pool
    function calcBorrowRate(
        uint256 expectedLiquidity,
        uint256 availableLiquidity
    ) external view returns (uint256);
}
