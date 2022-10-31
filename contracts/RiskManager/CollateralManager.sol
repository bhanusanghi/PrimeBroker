// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;

import {ICollateralManager} from "../Interfaces/ICollateralManager.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {IPriceOracle} from "../Interfaces/IPriceOracle.sol";
import {MarginManager} from "../MarginAccount/MarginManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {SettlementTokenMath} from "../Libraries/SettlementTokenMath.sol";

contract CollateralManager is ICollateralManager {
  using SafeMath for uint256;
  using SettlementTokenMath for uint256;
  using SafeCastUpgradeable for uint256;
  using SafeCastUpgradeable for int256;
  using SignedMath for int256;

  MarginManager  public marginManager;
  IPriceOracle public priceOracle;
  address[] public allowedCollateral;// allowed tokens
  uint256[] public collateralWeight;
  uint8 private constant baseDecimals = 6;// @todo get from vault in initialize func
  // address=> decimals for allowed tokens so we don't have to make external calls
  mapping(address=> uint8) private _decimals;
  mapping(address=>bool) public isAllowed;
  mapping(address => mapping(address => uint256)) internal _balance;
    function initialize(
            address _marginManager,
            address _priceOracle
        ) public  {
          marginManager = MarginManager(_marginManager);
          priceOracle=IPriceOracle(_priceOracle);
        }
  function addAllowedCollateral(address[] calldata _allowed) public {
    uint8 len = _allowed.length.toUint8();
    for(uint8 i=0;i<len;i++) {
      allowedCollateral.push(_allowed[i]);
      isAllowed[_allowed[i]]=true;
      _decimals[_allowed[i]]= ERC20(_allowed[i]).decimals();
    }
  }

 function addCollateral(address token, uint256 amount) external{
    require(isAllowed[token],"This token as collateral not allowed");
    IMarginAccount marginAcc = IMarginAccount(marginManager.marginAccounts(msg.sender));
    marginAcc.addCollateral(msg.sender,token,amount);
    _balance[address(marginAcc)][token] = amount;
 }
 function withdrawCollatral() external{}

 function totalCollatralValue(address marginAccount) external returns(uint256 totalAmount){
        uint8 len = allowedCollateral.length.toUint8();
        for (uint8 i = 0; i < len; i++) {
            address token = allowedCollateral[i];
            totalAmount = totalAmount.add(
              _balance[marginAccount][token].convertTokenDecimals(_decimals[token], baseDecimals)
            );
            // priceOracle.convertToUSD(
            //     IERC20(token).balanceOf(marginAccount),
            //     token
            // );.mul(w)
        }
 }

}
