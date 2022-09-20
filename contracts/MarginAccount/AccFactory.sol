pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ACLTrait} from "../core/ACLTrait.sol";

import {ZeroAddressException} from "../interfaces/IErrors.sol";

import "hardhat/console.sol";

contract MarginManager is ACLTrait, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;

    mapping(address => address) public override creditAccounts;

    modifier xyz() {
        _;
    }

    constructor() {}

    function openMarginAccount() external returns (address) {
        /**MarginAccount.new()
         approve tokens max
        
        **/
    }

    function closeMarginAccount() external {}

    function _approveTokens() private {}
    // function transferAccount(address from, address to) external {}
}
