pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ACLTrait} from "../core/ACLTrait.sol";

import {ZeroAddressException} from "../interfaces/IErrors.sol";

import "hardhat/console.sol";

contract MarginAccount {
    modifier xyz() {
        _;
    }

    constructor() {}

    function addCollateral() external {}

    function RemoveCollateral() external {
        /**
        check margin, open positions
        withdraw
         */
    }

    function openPosition() external {
        /**
        check margin and open positions
         */
    }

    function updatePosition() external {
        /**
        check margin and increase/decrease positions
         */
    }

    function closePosition() external {
        /**
        preview close on origin, if true close or revert
        take fees and interest
         */
    }

    function Liquidate() external {}
}
