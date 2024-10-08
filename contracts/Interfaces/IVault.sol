// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

interface IVault {
    // events

    // Emits each time when Interest Rate model was changed
    event InterestRateModelUpdated(address indexed newInterestRateModel);

    // Emits each time when new credit Manager was connected
    event NewCreditManagerConnected(address indexed creditManager);

    // Emits each time when borrow forbidden for credit manager
    event BorrowForbidden(address indexed creditManager);

    // Emits each time when Credit Manager borrows money from pool
    event Borrow(
        address indexed creditManager,
        address indexed creditAccount,
        uint256 amount
    );

    // Emits each time when Credit Manager repays money from pool
    event Repay(
        address indexed creditManager,
        uint256 borrowedAmount,
        uint256 interest,
        uint256 profit,
        uint256 loss
    );

    function borrow(address borrower, uint256 amount) external;

    function repay(
        address borrower,
        uint256 amount,
        uint256 interestAccrued
        // uint256 loss,
        // uint256 profit
    ) external;

    // view/getters
    function expectedLiquidity() external view returns (uint256);

    function calcLinearCumulative_RAY() external view returns (uint256);

    function asset() external view returns (address);

    function _cumulativeIndex_RAY() external view returns (uint256);

    function getInterestRateModel() external view returns (address);
}
