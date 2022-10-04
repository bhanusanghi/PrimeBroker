pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IPriceOracle} from "../../Interfaces/IPriceOracle.sol";
import {SNXRiskManager} from "./SNXRiskManager.sol";
import {MarginAccount} from "../MarginAccount.sol";
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
        address[] memory destinations,
        bytes[] memory data
    ) external returns (uint256 tokens) {
        //calls {dest:calldata}
        // snxRiskManager.varifyData(calls)=> snx.sported tx enumerate check if data is correct, tokens_to_transfer
        // destinations[0] = address(0);
        // dataArray[0] = data; // might need to copy it so maybe send back pointers
        tokens = 100;
        uint256 spot = _spotAssetValue(marginAcc);
        (uint256 margin, int256 unRealizedPnL) = _derivativesPositionValue(
            marginAcc
        );
        uint256 totalDebt = 1; // keep a total debt var in margin account
        SNXRiskManager rm = new SNXRiskManager();
        uint256 transferAmount;
        (transferAmount, tokens) = rm.txDataDecoder(data);
        // if (
        //     ((int256(spot) + unRealizedPnL) * 2) >
        //     int256(transferAmount + totalDebt)
        // ) {
        // @todo use proper lib for it
        MarginAccount(marginAcc).execMultiTx(destinations, data);
        // }
        // swtich case
        // if (aandu bandu formula+tokens_to_transfer> minimum margin){
        //
        // }
        /**
        AB = Account Balance ( spot asset value)
        UP = Unrealised PnL (unRealizedPnL)
        MIP = Margin in Positions (margin from all positions)
        MM = Maintenance Margin % 30% for now
        AB+UP-IM-MM>0
         */
        // return ();
    }

    function _spotAssetValue(address marginAccount) private returns (uint256) {
        uint256 totalAmount = 0;
        uint256 len = allowedTokens.length;
        for (uint256 i = 0; i < len; i++) {
            address token = allowedTokens[i];
            totalAmount += IERC20(token).balanceOf(marginAccount) * 1; // hardcode usd price
            // priceOracle.convertToUSD(
            //     IERC20(token).balanceOf(marginAccount),
            //     token
            // );
        }
        return totalAmount;
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
