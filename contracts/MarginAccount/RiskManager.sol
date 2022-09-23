pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ACLTrait} from "../core/ACLTrait.sol";

import {ZeroAddressException} from "../interfaces/IErrors.sol";

import "hardhat/console.sol";

contract RiskManager is ACLTrait, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;

    mapping(address => address) public override creditAccounts;

    modifier xyz() {
        _;
    }

    constructor() {}

    function AllowNewTrade() external returns (bool) {
        return true;
    }

    function _spotAssetValue() private {}

    function _derivativesPositionValue() private {}

    function TotalPositionValue() external {}

    function TotalLeverage() external {}
}
