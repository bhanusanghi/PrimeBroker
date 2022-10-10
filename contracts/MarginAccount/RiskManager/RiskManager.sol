pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IPriceOracle} from "../../Interfaces/IPriceOracle.sol";
import {SNXRiskManager} from "./SNXRiskManager.sol";
import {MarginAccount} from "../MarginAccount.sol";
import {Vault} from "../../MarginPool/Vault.sol";
import "hardhat/console.sol";

contract RiskManager is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    IPriceOracle public priceOracle;
    Vault public vault;
    address[] public allowedTokens;
    modifier xyz() {
        _;
    }
    uint256 public initialMarginFactor = 35; //in percent
    // 1000-> 2800$
    // protocol to riskManager mapping
    // perpfi address=> perpfiRisk manager
    mapping(address => address) public riskManagers;

    constructor() {}

    function setPriceOracle(address oracle) external {
        // onlyOwner
        priceOracle = IPriceOracle(oracle);
    }

    function setVault(address _vault) external {
        vault = Vault(_vault);
    }

    function NewTrade(
        address marginAcc,
        address protocolAddress,
        address[] memory destinations,
        bytes[] memory data
    ) external returns (uint256 tokens) {
        tokens = 100;
        int256 positionSize;
        uint256 totalNotioanl;
        int256 PnL;
        (totalNotioanl, PnL) = MarginAccount(marginAcc).getPositionsValue();
        uint256 freeMargin = getFreeMargin(marginAcc, PnL);

        SNXRiskManager rm = new SNXRiskManager();
        uint256 maxTransferAmount = freeMargin -
            (totalNotioanl + uint256(positionSize));
        uint256 transferAmount;
        (transferAmount, positionSize) = rm.txDataDecoder(data);
        // if (freeMargin >= uint256(absVal(positionSize))) {
        console.log(freeMargin, transferAmount, "f");
        require(
            freeMargin >= (totalNotioanl + uint256(absVal(positionSize))),
            "Extra margin not allowed"
        );
        if (positionSize > 0) {
            vault.lend(transferAmount, marginAcc);
            MarginAccount(marginAcc).execMultiTx(destinations, data);
            MarginAccount(marginAcc).updatePosition(
                protocolAddress,
                positionSize,
                transferAmount
            ); // @todo update it with vault-MM link

            //         function repay(
            // uint256 borrowedAmount, // exact amount that is returned as principle
            // uint256 loss,
            // uint256 profit
        } else if (positionSize < 0) {
            // vault.repay()
            console.log("repay time");
            MarginAccount(marginAcc).execMultiTx(destinations, data);
            MarginAccount(marginAcc).updatePosition(
                protocolAddress,
                positionSize,
                transferAmount
            );
        } else {
            revert("margin kam pad gya na");
        }
        // if (
        //     ((int256(spot) + unRealizedPnL) * 2) >
        //     int256(transferAmount + totalDebt)
        // ) {
        // @todo use proper lib for it

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

    function getFreeMargin(address marginAccount, int256 PnL)
        public
        view
        returns (uint256)
    {
        console.log("hohoho", spotAssetValue(marginAccount));
        console.log(
            (uint256(int256(spotAssetValue(marginAccount)) + PnL) * 100)
        );
        return (((uint256(int256(spotAssetValue(marginAccount)) + PnL) * 100) /
            initialMarginFactor) -
            MarginAccount(marginAccount).totalBorrowed());

        /**
                (asset+PnL)*100/initialMarginFactor
             */
    }

    function addAllowedTokens(address token) public {
        allowedTokens.push(token);
    }

    function spotAssetValue(address marginAccount)
        public
        view
        returns (uint256 totalAmount)
    {
        // @todo have a seperate variable for vault assets so that lent and deposited assets don't mix up
        uint256 len = allowedTokens.length;
        console.log("spot val");
        for (uint256 i = 0; i < len; i++) {
            address token = allowedTokens[i];
            console.log("spot val", IERC20(token).balanceOf(marginAccount));
            totalAmount += IERC20(token).balanceOf(marginAccount) * 1; // hardcode usd price
            // priceOracle.convertToUSD(
            //     IERC20(token).balanceOf(marginAccount),
            //     token
            // );
        }
        return totalAmount;
    }

    function absVal(int256 val) public view returns (int256) {
        return val < 0 ? -val : val;
    }

    function getPnL(address marginAccount)
        public
        view
        returns (uint256 notionalValue, int256 PnL)
    {
        uint256 amount;
        // for each protocol or iterate on positions and get value of positions
        return (1, 1);
    }

    function TotalPositionValue() external {}

    function TotalLeverage() external {}
}
