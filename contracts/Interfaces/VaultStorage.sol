// SPDX-License-Identifier: GPL-3.0-or-later
import {IInterestRateModel} from "./IInterestRateModel.sol";

abstract contract VaultStorage {
    uint256 totalBorrowed;
    uint256 expectedLiquidity;
    IInterestRateModel interestRateModel; // move this later to contractName => implementationAddress contract registry

    mapping(address => bool) lendingAllowed;
    mapping(address => bool) repayingAllowed;
    address[] whitelistedCreditors;

    // Cumulative index in RAY
    uint256 public _cumulativeIndex_RAY;
    // Current borrow rate in RAY: https://dev.gearbox.fi/developers/pools/economy#borrow-apy
    uint256 public borrowAPY_RAY;

    // used to calculate next timestamp values quickly
    uint256 expectedLiquidityLastUpdated;
    uint256 timestampLastUpdated;
}
