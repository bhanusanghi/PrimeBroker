// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;

import {ICollateralManager} from "../Interfaces/ICollateralManager.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {IPriceOracle} from "../Interfaces/IPriceOracle.sol";
import {MarginManager} from "../MarginAccount/MarginManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CollateralManager is ICollateralManager {
  MarginManager  public marginManager;
  IPriceOracle public priceOracle;
  address[] public allowedCollateral;// allowed tokens
  uint256[] public collateralWeight;
  mapping(address=>bool) public isAllowed;
  mapping(address => mapping(address => int256)) internal _balance;
    function initialize(
            address _marginManager,
            address _priceOracle
        ) public  {
          marginManager = MarginManager(_marginManager);
          priceOracle=IPriceOracle(_priceOracle);
        }
  function addAllowedCollateral(address[] calldata _allowed) public {
    uint256 len = _allowed.length;
    for(uint256 i=0;i<len;i++){
      allowedCollateral.push(_allowed[i]);
      isAllowed[_allowed[i]]=true;
    }
  }

 function addCollateral(address token, uint256 amount) external{
    require(isAllowed[token],"This token as collateral not allowed");
    IMarginAccount marginAcc = IMarginAccount(marginManager.marginAccounts(msg.sender));
    marginAcc.addCollateral(msg.sender,token,amount);
    _balance[address(marginAcc)][token] = int256(amount);
 }
 function withdrawCollatral() external{}

 function totalCollatralValue(address marginAccount) external returns(uint256 totalAmount){
        uint256 len = allowedCollateral.length;
        for (uint256 i = 0; i < len; i++) {
            address token = allowedCollateral[i];
            totalAmount+= uint256((_balance[marginAccount][token]))/(10**ERC20(token).decimals());
            // priceOracle.convertToUSD(
            //     IERC20(token).balanceOf(marginAccount),
            //     token
            // );.mul(w)
        }
        return totalAmount*(10**6);
 }

}
