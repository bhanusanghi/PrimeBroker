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

    function NewTrade(
        address marginAcc,
        address protocolAddress,
        bytes calldata data
    )
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
        uint256 spot = _spotAssetValue(marginAcc);
        (uint256 margin, int256 unRealizedPnL) = _derivativesPositionValue(
            marginAcc
        );
        /**
        AB = Account Balance ( spot asset value)
        UP = Unrealised PnL (unRealizedPnL)
        MIP = Margin in Positions (margin from all positions)
        MM = Maintenance Margin % 30% for now
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
        returns (uint256, int256)
    {
        uint256 amount;
        // for each protocol or iterate on positions and get value of positions
        return (0, 0);
    }

    function TotalPositionValue() external {}

    function TotalLeverage() external {}
}
