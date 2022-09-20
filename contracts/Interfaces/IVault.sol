// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IVault is IERC4626 {
    // events

    // Emits each time when Interest Rate model was changed
    event InterestRateModelUpdated(address indexed newInterestRateModel);

    // Emits each time when new credit Manager was connected
    event NewCreditManagerConnected(address indexed creditManager);

    // Emits each time when borrow forbidden for credit manager
    event BorrowForbidden(address indexed creditManager);

    // Emits after expected liquidity limit update
    // event NewExpectedLiquidityLimit(uint256 newLimit);

    // Emits each time when withdraw fee is udpated
    // event NewWithdrawFee(uint256 fee);

    function lend(uint256 amount, address borrower) external;

    function repay(
        uint256 amount,
        uint256 loss,
        uint256 profit
    ) external;

    // view/getters
    function expectedLiquidity() external view returns (uint256);

    function calcLinearCumulative_RAY() external view returns (uint256);

    // setters
}
