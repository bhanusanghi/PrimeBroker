pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IPriceOracle} from "../../Interfaces/IPriceOracle.sol";

import "hardhat/console.sol";

contract RiskManager is ReentrancyGuard {
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

    function setPriceOracle(address oracle) external {
        // onlyOwner
        priceOracle = IPriceOracle(oracle);
    }

    function NewTrade(bytes calldata data)
        external
        returns (
            address[] destinations,
            bytes[] memory dataArray,
            uint256 tokens
        )
    {
        destinations[0] = "0x0";
        dataArray[0] = data; // might need to copy it so maybe send back pointers
        tokens = 100;
        // total asset value+total derivatives value(excluding margin)
        // total leverage ext,int
        /**
        _spotAssetValue + total
        AB = Account Balance ( spot asset value)
        UP = Unrealised PnL ()
        IM = Initial Margin
        MM = Maintenance Margin
        AB+UP-IM-MM>0
         */
        return ();
    }

    function _spotAssetValue(address marginAccount) private {
        uint256 totalAmount = 0;
        uint256 len = allowedTokens.length;
        for (uint256 i = 0; i < len; i++) {
            address token = allowedTokens[i];
            totalAmount += priceOracle.convertToUSD(
                IERC20(token).balanceOf(marginAccount),
                token
            );
        }
    }

    function _derivativesPositionValue(address marginAccount)
        private
        returns (uint256)
    {
        uint256 amount;
        // for each protocol or iterate on positions and get value of positions
        return amount;
    }

    function TotalPositionValue() external {}

    function TotalLeverage() external {}
}
