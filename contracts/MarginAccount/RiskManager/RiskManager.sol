pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import {ACLTrait} from "../core/ACLTrait.sol";
import {IPriceOracle} from "../../Interfaces/IPriceOracle.sol";
import {ZeroAddressException} from "../../Interfaces/IErrors.sol";

import "hardhat/console.sol";

contract RiskManager is ACLTrait, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    IPriceOracle public priceOracle;
    address[] public allowedTokens;
    modifier xyz() {
        _;
    }
    // protocol to riskManager mapping
    // perpfi address=> perpfiRisk manager
    mapping(address => address) public riskManagers;
    constructor() {}
    function setPriceOracle(addres oracle) external {
      // onlyOwner
      priceOracle = IPriceOracle(oracle);
    }

    function AllowNewTrade(bytes calldata data) external returns (bool) {
      // total asset value+total derivatives value(excluding margin)
      // total leverage ext,int
        return true;
    }

    function _spotAssetValue(address marginAccount) private {
        uint256 totalAmount = 0;
        uint256 len = allowedTokens.length;
        for (uint256 i = 0; i < len; i++) {
            address token =allowedTokens[i];
            totalAmount +=priceOracle.convertToUSD(IERC20(token).balanceOf(marginAccount), token);;
        }
    }

    function _derivativesPositionValue(address marginAccount) private returns(uint256){
      uint256 amount;
      // for each protocol or iterate on positions and get value of positions
      return amount;
    }


    function TotalPositionValue() external {}

    function TotalLeverage() external {}
}
