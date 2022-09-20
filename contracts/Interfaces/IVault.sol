// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";

abstract contract IVaultStorage {

  uint256 totalBorrowed;
  
  // used to calculate next timestamp values quickly
  uint256 liquidityLastUpdated;
  uint256 timestampLastUpdated;
}

interface IVault is IERC4626 {
    // assuming managers will repay for an account.

    function lend(uint256 amount, address borrower) external;

    function repay(
        uint256 amount,
        uint256 loss,
        uint256 profit
    ) external;


}
