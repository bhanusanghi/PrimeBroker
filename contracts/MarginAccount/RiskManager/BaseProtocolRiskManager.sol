pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IPriceOracle} from "../../Interfaces/IPriceOracle.sol";

import "hardhat/console.sol";

contract BaseProtocolRiskManager {
    function getTotalPnL(address marginAcc) public virtual returns (int256);

    function getTotalPositionSize(address marginAcc)
        public
        virtual
        returns (uint256);

    function getTotalAssetsValue(address marginAcc)
        public
        virtual
        returns (uint256);
}
