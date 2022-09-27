pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IPriceOracle} from "../../Interfaces/IPriceOracle.sol";
import {BaseProtocolRiskManager} from "./BaseProtocolRiskManager.sol";
import "hardhat/console.sol";

contract PerpfiRiskManager is BaseProtocolRiskManager {
    // address public perp
    // function getPositionValue(address marginAcc) public override {}
}
