pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ACLTrait} from "../core/ACLTrait.sol";
import {RiskManager} from "./RiskManager.sol";
import {ZeroAddressException} from "../interfaces/IErrors.sol";

import "hardhat/console.sol";

contract MarginManager is ACLTrait, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    RiskManager public riskManager;
    address public vault;
    address public riskManager;
    address public vault;
    uint256 public liquidationPenaulty;

    // mapping(address => address) public creditAccounts;
    mapping(address => uint256) public collatralRatio; // non-zero means allowed
    // function transferAccount(address from, address to) external {}
    modifier xyz() {
        _;
    }

    constructor() {}

    function SetCollatralRatio(address token, uint256 value)
        external
    //onlyOwner
    {
        collatralRatio[token] = value;
    }

    function SetPenaulty(uint256 value) external {
        // onlyOwner
        liquidationPenaulty = value;
    }

    function SetRiskManager(address riskmgr) external {
        // onlyOwner
        riskManager = RiskManager(riskmgr);
    }

    function addPosition() external {
        /**
        if RiskManager.AllowNewTrade
            open positions
         */
    }

    function updatePosition(address protocol, bytes calldata data) external {
        if (riskManager.AllowNewTrade(data)) {
            //marginacc.execute
        }
    }

    function closePosition() external {
        /**
        preview close on origin, if true close or revert
        take fees and interest
         */
    }

    function openMarginAccount() external returns (address) {
        /**MarginAccount.new()
         approve tokens max
        **/
    }

    function RemoveCollateral() external {
        /**
        check margin, open positions
        withdraw
         */
    }

    function closeMarginAccount() external {}

    function _approveTokens() private {}
}
