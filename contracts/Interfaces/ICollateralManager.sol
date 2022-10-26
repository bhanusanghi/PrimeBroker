// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;


interface ICollateralManager {


 function addCollateral(address token, uint256 amount) external;
 function withdrawCollatral() external;
 function totalCollatralValue(address marginAccount) external returns(uint256 amount);

}
